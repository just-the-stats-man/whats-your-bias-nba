source('scripts/load.R');con<-connect_warehouse()
tryCatch({
  DBI::dbExecute(con,'SET threads=4');DBI::dbExecute(con,"SET memory_limit='3GB'")
  baseline<-readRDS('data/processed/phase3/phase2_baseline.rds')
  stopifnot(identical(reconstruction_version,baseline$method))
  signature<-function()do.call(rbind,lapply(c('shot_attempts','possessions','lineups','lineup_players','reconstruction_status','lineup_minute_checks','datasets','shot_recovery_candidates'),function(t){z<-DBI::dbGetQuery(con,paste0('SELECT count(*) n,CAST(bit_xor(hash(t)) AS VARCHAR) checksum FROM ',t,' t'));data.frame(table=t,z)}))
  before<-signature();stopifnot(publish_shot_recovery(con)==0L,all(publish_physical_recovery(con)==0L));after<-signature()
  stopifnot(identical(before,after));utils::write.csv(after,'docs/phase3/idempotence.csv',row.names=FALSE)
  checks<-rbind(warehouse_integrity_report(con),historical_integrity(con),execution_integrity(con),shot_recovery_integrity(con),physical_recovery_integrity(con),phase3_preservation(con))
  inputs<-DBI::dbReadTable(con,'datasets');actual<-vapply(inputs$raw_path,file_sha256,character(1))
  hashes<-data.frame(dataset_id=inputs$dataset_id,path=inputs$raw_path,sha256=inputs$sha256,actual_sha256=actual,passed=inputs$sha256==actual)
  utils::write.csv(hashes,'data/processed/phase3/final_input_hashes.csv',row.names=FALSE)
  b<-baseline$inputs;preserved<-vapply(b$raw_path,file_sha256,character(1))==b$sha256
  frozen<-utils::read.csv('data/processed/phase3/nba_normalized_hashes.csv');nba_files<-vapply(frozen$path,file_sha256,character(1))==frozen$sha256
  nba<-DBI::dbReadTable(con,'historical_snapshots');nba_raw<-vapply(nba$path,file_sha256,character(1))==nba$sha256
  index<-utils::read.csv('data/processed/phase3/physical_stage.csv',colClasses=c(game_id='character'))
  rds<-vapply(index$path,file_sha256,character(1))==index$sha256
  checks<-rbind(checks,data.frame(check=c('registered_input_hashes','original_9645_input_hashes','frozen_nba_normalized_files','nba_raw_snapshots','physical_checkpoint_hashes','affected_certified_possession_regressions','affected_certified_lineup_regressions'),violations=c(sum(!hashes$passed),sum(!preserved),sum(!nba_files),sum(!nba_raw),sum(!rds),sum(index$possessions_before=='reconciled' & !index$possession_pass),sum(index$lineups_before=='reconciled' & !index$lineup_pass)),passed=c(all(hashes$passed),length(preserved)==9645L && all(preserved),length(nba_files)==19L && all(nba_files),length(nba_raw)==6L && all(nba_raw),all(rds),all(index$possession_pass[index$possessions_before=='reconciled']),all(index$lineup_pass[index$lineups_before=='reconciled']))))
  utils::write.csv(checks,'docs/phase3/final_integrity.csv',row.names=FALSE);stopifnot(all(checks$passed))
  phase3_reports(con)
  utils::write.csv(index,'docs/phase3/recovery_attempts.csv',row.names=FALSE,na='')
  utils::write.csv(DBI::dbGetQuery(con,'SELECT * FROM reconstruction_component_methods ORDER BY game_id,component'),'docs/phase3/component_methods.csv',row.names=FALSE)
  utils::write.csv(DBI::dbGetQuery(con,'SELECT * FROM recovery_transformations ORDER BY game_id,event_id,rule,evidence'),'docs/phase3/transformation_audit.csv',row.names=FALSE,na='')
  utils::write.csv(data.frame(family=c('registered_inputs','original_registered_inputs','frozen_phase2_tables','frozen_nba_normalized_files','nba_raw_snapshots','physical_checkpoints'),verified=c(nrow(inputs),length(preserved),nrow(baseline$tables),length(nba_files),length(nba_raw),length(rds))),'docs/phase3/hash_verification.csv',row.names=FALSE)
  cat(nrow(checks),'checks passed;',nrow(inputs),'registered hashes;',length(rds),'checkpoint hashes\n')
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
