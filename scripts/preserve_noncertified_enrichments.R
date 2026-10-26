source('scripts/load.R');con<-connect_warehouse()
tryCatch({
  DBI::dbExecute(con,'SET threads=4');DBI::dbExecute(con,"SET memory_limit='3GB'")
  indices<-lapply(c('terminal_stage','roster_stage'),function(k)utils::read.csv(paste0('data/processed/phase4/',k,'.csv'),colClasses=c(game_id='character')))
  inputs<-do.call(rbind,indices);inputs<-inputs[!inputs$passed,]
  pieces<-lapply(seq_len(nrow(inputs)),function(i){stopifnot(file_sha256(inputs$path[i])==inputs$sha256[i]);r<-readRDS(inputs$path[i]);c<-r$candidates;c$staging_artifact_path<-inputs$path[i];c$staging_artifact_sha256<-inputs$sha256[i];c$method<-r$method;c})
  all<-do.call(rbind,pieces)
  DBI::dbWriteTable(con,'_staged_values',all,temporary=TRUE,overwrite=TRUE)
  DBI::dbExecute(con,"ATTACH 'data/processed/phase4/baseline.duckdb' AS phase3_frozen (READ_ONLY)")
  rows<-DBI::dbGetQuery(con,"SELECT s.* FROM _staged_values s JOIN phase3_frozen.main.shot_recovery_candidates b USING(game_id,event_id) WHERE b.points_attempted IS NULL AND s.points_attempted IS NOT NULL AND s.certification_status='noncertified'")
  DBI::dbExecute(con,'DETACH phase3_frozen')
  unchanged<-FALSE
  if(DBI::dbExistsTable(con,'phase4_noncertified_shot_enrichments')) {
    meaningful<-setdiff(names(rows),c('dataset_id','staging_artifact_path','staging_artifact_sha256'))
    cols<-paste(DBI::dbQuoteIdentifier(con,meaningful),collapse=',')
    DBI::dbWriteTable(con,'_new_enrichments',rows,temporary=TRUE,overwrite=TRUE)
    a<-DBI::dbGetQuery(con,paste0('SELECT count(*) n FROM (SELECT ',cols,' FROM _new_enrichments EXCEPT SELECT ',cols,' FROM phase4_noncertified_shot_enrichments)'))$n
    b<-DBI::dbGetQuery(con,paste0('SELECT count(*) n FROM (SELECT ',cols,' FROM phase4_noncertified_shot_enrichments EXCEPT SELECT ',cols,' FROM _new_enrichments)'))$n
    unchanged<-a==0 && b==0 && nrow(rows)==DBI::dbGetQuery(con,'SELECT count(*) n FROM phase4_noncertified_shot_enrichments')$n
  }
  if(!unchanged) {
  signature<-digest::digest(list(inputs[c('signature','sha256')],body(shot_recovery_classify)),algo='sha256')
  id<-paste0('phase4:noncertified-values:',signature);path<-file.path('data/processed/phase4',paste0('noncertified-values-',substr(signature,1,16),'.parquet'))
  rows$evidence_dataset_id<-id
  if(!file.exists(path))arrow::write_parquet(rows,path)
  DBI::dbWriteTable(con,'phase4_noncertified_shot_enrichments',rows,overwrite=TRUE)
  source<-DBI::dbGetQuery(con,"SELECT * FROM historical_snapshots WHERE kind='pbp'")
  prior<-DBI::dbGetQuery(con,'SELECT 1 FROM datasets WHERE dataset_id=?',params=list(id))
  if(!nrow(prior))upsert_rows(con,'datasets',data.frame(dataset_id=id,source_id=source$source_id,url=source$url,revision='phase4-staging-value-enrichments-v1',retrieved_at=Sys.time(),sha256=file_sha256(path),raw_path=path,row_count=nrow(rows)),'dataset_id')
  parents<-unique(c(rows$source_dataset_id,rows$canonical_event_dataset_id,rows$reference_snapshot_id));parents<-parents[!is.na(parents)]
  upsert_rows(con,'dataset_dependencies',data.frame(dataset_id=id,parent_dataset_id=parents,transformation='Known-value derivations retained from failed whole-game certification; versioned staging evidence only, not additional independent attempts'),c('dataset_id','parent_dataset_id'))
  }
  utils::write.csv(DBI::dbGetQuery(con,'SELECT season,method,count(*) derived_value_versions,count(DISTINCT game_id||\':\'||event_id) distinct_attempts FROM phase4_noncertified_shot_enrichments GROUP BY ALL ORDER BY ALL'),'docs/phase4/noncertified_value_enrichments.csv',row.names=FALSE)
  cat(nrow(rows),'noncertified value derivations preserved;',if(unchanged)'unchanged semantic evidence; no new registry rows;' else '', 'no canonical promotion\n')
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
