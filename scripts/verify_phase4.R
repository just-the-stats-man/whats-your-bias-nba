source('scripts/load.R');con<-connect_warehouse()
tryCatch({
  DBI::dbExecute(con,'SET threads=4');DBI::dbExecute(con,"SET memory_limit='3GB'")
  signature<-function()do.call(rbind,lapply(c('shot_attempts','shot_recovery_candidates','shot_recovery_checks','possessions','lineups','lineup_players','reconstruction_status','lineup_minute_checks','datasets','phase4_verified_player_boxes'),function(t)cbind(data.frame(table=t),DBI::dbGetQuery(con,paste0('SELECT count(*) n,CAST(bit_xor(hash(t)) AS VARCHAR) checksum FROM ',t,' t')))))
  before<-signature();stopifnot(publish_terminal_shots(con)['canonical_added']==0L,publish_terminal_shots(con,'data/processed/phase4/roster_stage.csv')['canonical_added']==0L)
  path<-file.path('data/processed/phase4/roster_shots',paste0('player-projection-',roster_projection_method(),'.rds'));stopifnot(publish_verified_roster_projection(con,path)==0L)
  stopifnot(publish_shot_recovery(con)==0L,all(publish_physical_recovery(con)==0L));after<-signature();stopifnot(identical(before,after))
  utils::write.csv(after,'docs/phase4/idempotence.csv',row.names=FALSE)
  install_research_views(con)
  checks<-rbind(warehouse_integrity_report(con),historical_integrity(con),execution_integrity(con),shot_recovery_integrity(con),physical_recovery_integrity(con),phase3_preservation(con),phase4_preservation(con),terminal_shot_integrity(con),roster_projection_integrity(con),research_integrity(con),staging_enrichment_integrity(con))
  inputs<-DBI::dbReadTable(con,'datasets');paths<-unique(inputs$raw_path);actual<-setNames(vapply(paths,file_sha256,character(1)),paths)
  hashes<-data.frame(dataset_id=inputs$dataset_id,path=inputs$raw_path,sha256=inputs$sha256,actual_sha256=unname(actual[inputs$raw_path]),passed=inputs$sha256==unname(actual[inputs$raw_path]))
  utils::write.csv(hashes,'data/processed/phase4/final_input_hashes.csv',row.names=FALSE)
  phase3_inputs<-readRDS('data/processed/phase4/baseline_inputs.rds');phase2<-readRDS('data/processed/phase3/phase2_baseline.rds');stopifnot(reconstruction_version==phase2$method)
  older<-phase2$inputs;original_ok<-unname(actual[older$raw_path])==older$sha256;phase3_ok<-unname(actual[phase3_inputs$raw_path])==phase3_inputs$sha256
  frozen<-utils::read.csv('data/processed/phase3/nba_normalized_hashes.csv');nba_norm<-vapply(frozen$path,file_sha256,character(1))==frozen$sha256
  nba<-DBI::dbReadTable(con,'historical_snapshots');nba_raw<-unname(actual[nba$path])==nba$sha256
  old_index<-utils::read.csv('data/processed/phase3/physical_stage.csv',colClasses=c(game_id='character'));old_files<-vapply(old_index$path,file_sha256,character(1))==old_index$sha256
  new_indices<-lapply(c('terminal_stage','roster_stage'),function(k)utils::read.csv(paste0('data/processed/phase4/',k,'.csv'),colClasses=c(game_id='character')));new_index<-do.call(rbind,new_indices);new_files<-vapply(new_index$path,file_sha256,character(1))==new_index$sha256
  add<-data.frame(check=c('registered_input_hashes','original_9645_input_hashes','frozen_nba_normalized_files','nba_raw_snapshots','physical_checkpoint_hashes','affected_certified_possession_regressions','affected_certified_lineup_regressions','original_phase3_9739_input_hashes','phase4_checkpoint_hashes','no_noncertified_enrichment_promoted'),violations=c(sum(!hashes$passed),sum(!original_ok),sum(!nba_norm),sum(!nba_raw),sum(!old_files),sum(old_index$possessions_before=='reconciled' & !old_index$possession_pass),sum(old_index$lineups_before=='reconciled' & !old_index$lineup_pass),sum(!phase3_ok),sum(!new_files),DBI::dbGetQuery(con,"SELECT count(*) n FROM phase4_noncertified_shot_enrichments WHERE certification_status!='noncertified'")$n))
  add$passed<-add$violations==0;checks<-rbind(checks,add)
  parents<-DBI::dbGetQuery(con,"SELECT count(*) n FROM dataset_dependencies d LEFT JOIN datasets p ON d.parent_dataset_id=p.dataset_id WHERE (d.dataset_id LIKE 'shot-recovery:phase4:%' OR d.dataset_id LIKE 'verified-roster-projection:%' OR d.dataset_id LIKE 'phase4:noncertified-values:%') AND p.dataset_id IS NULL")$n
  checks<-rbind(checks,data.frame(check='phase4_registered_parent_lineage',violations=parents,passed=parents==0))
  utils::write.csv(checks,'docs/phase4/final_integrity.csv',row.names=FALSE);stopifnot(all(checks$passed),sum(checks$check%in%utils::read.csv('docs/phase3/final_integrity.csv')$check)==152L)
  utils::write.csv(data.frame(family=c('current_registered_inputs','original_phase3_registered_inputs','original_phase2_registered_inputs','frozen_nba_normalized_files','nba_raw_snapshots','phase3_physical_checkpoints','phase4_shot_checkpoints'),verified=c(nrow(inputs),nrow(phase3_inputs),nrow(older),length(nba_norm),length(nba_raw),length(old_files),length(new_files))),'docs/phase4/hash_verification.csv',row.names=FALSE)
  phase4_shot_coverage(con);phase3_reports(con,'docs/phase4/current')
  cat(nrow(checks),'checks passed;',nrow(inputs),'registered hashes;',length(new_files),'Phase 4 checkpoint hashes\n')
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
