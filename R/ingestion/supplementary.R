supplementary_schema <- function(con) {
  DBI::dbExecute(con,'CREATE TABLE IF NOT EXISTS supplementary_snapshots (sha256 VARCHAR,provider VARCHAR,endpoint VARCHAR,request_hash VARCHAR,raw_path VARCHAR,received_at TIMESTAMP,schema_id VARCHAR,terms_url VARCHAR,permission_status VARCHAR,live_validated BOOLEAN,PRIMARY KEY(provider,request_hash,sha256))')
  DBI::dbExecute(con,'CREATE TABLE IF NOT EXISTS supplementary_export_records (snapshot_sha256 VARCHAR,source_row BIGINT,provider VARCHAR,observational_unit VARCHAR,native_key VARCHAR,validation_status VARCHAR,raw_record_json VARCHAR,PRIMARY KEY(snapshot_sha256,source_row))')
  DBI::dbExecute(con,'CREATE TABLE IF NOT EXISTS supplementary_permission_receipts (provider VARCHAR,receipt_id VARCHAR,terms_url VARCHAR,local_retention BOOLEAN,modeling BOOLEAN,derived_publication BOOLEAN,raw_redistribution BOOLEAN,receipt_json VARCHAR,PRIMARY KEY(provider,receipt_id))')
}

supplementary_append_receipt <- function(con,row) {
  DBI::dbWriteTable(con,'_supplementary_receipt',row,temporary=TRUE,overwrite=TRUE)
  DBI::dbExecute(con,'INSERT OR IGNORE INTO supplementary_snapshots BY NAME SELECT * FROM _supplementary_receipt')
  DBI::dbRemoveTable(con,'_supplementary_receipt')
}

ingest_dunkapi_snapshot <- function(con,receipt) {
  stopifnot(identical(receipt$provider,'dunkapi'),identical(receipt$endpoint,'get_plays'),identical(receipt$permission_status,'approved_internal_use_no_raw_redistribution'),file_sha256(receipt$path)==receipt$sha256)
  payload<-jsonlite::fromJSON(receipt$path,simplifyVector=FALSE);rows<-normalize_dunkapi_plays(payload,receipt$sha256)
  supplementary_schema(con)
  DBI::dbWithTransaction(con,{
    record<-as.data.frame(receipt[c('sha256','provider','endpoint','request_hash','received_at','schema_id','terms_url','permission_status','live_validated')],stringsAsFactors=FALSE);record$raw_path<-receipt$path
    supplementary_append_receipt(con,record)
    if(nrow(rows)) {
      if(!DBI::dbExistsTable(con,'dunkapi_play_observations'))DBI::dbWriteTable(con,'dunkapi_play_observations',rows[FALSE,])
      upsert_rows(con,'dunkapi_play_observations',rows,c('snapshot_sha256','source_row'))
    }
    upsert_rows(con,'sources',data.frame(source_id='dunkapi',url='https://dunkapi.com/',license='Provider terms; internal storage/modeling; no standalone raw redistribution',attribution='DunkAPI / OWSH Unlimited LLC; upstream public-data lineage unverified'),'source_id')
    upsert_rows(con,'datasets',data.frame(dataset_id=paste0('dunkapi:',receipt$sha256),source_id='dunkapi',url='https://mcp.dunkapi.com/v1/get_plays',revision=receipt$schema_id,retrieved_at=receipt$received_at,sha256=receipt$sha256,raw_path=receipt$path,row_count=nrow(rows)),'dataset_id')
  })
  invisible(rows)
}

# No provider CSV layout is guessed. These are raw, permissioned staging rows;
# a declared aggregate/filter unit cannot become individual-shot observations.
ingest_authorized_export <- function(con,path,provider,observational_unit,key_columns,permission) {
  if(!is.list(permission)||!isTRUE(permission$local_retention)||!isTRUE(permission$approved)||!nzchar(permission$terms_url)||!nzchar(permission$receipt_id))stop('Explicit export/retention permission receipt required')
  if(any(!names(permission)%in%c('provider','terms_url','receipt_id','approved','local_retention','modeling','derived_publication','raw_redistribution','evidence_path','evidence_sha256')))stop('Unsupported permission receipt fields')
  if(!observational_unit%in%c('player_season','player_game_filter','team_game_filter','shot_annotation','lineup_aggregate'))stop('Unrecognized observational unit')
  data<-utils::read.csv(path,colClasses='character',check.names=FALSE,na.strings=character())
  if(!length(key_columns)||!all(key_columns%in%names(data)))stop('Explicit source key columns required')
  sha<-file_sha256(path);keys<-vapply(seq_len(nrow(data)),function(i)as.character(jsonlite::toJSON(as.list(data[i,key_columns,drop=FALSE]),auto_unbox=TRUE)),character(1))
  dup<-duplicated(keys)|duplicated(keys,fromLast=TRUE)
  rows<-data.frame(snapshot_sha256=rep(sha,nrow(data)),source_row=seq_len(nrow(data)),provider=rep(provider,nrow(data)),observational_unit=rep(observational_unit,nrow(data)),native_key=keys,validation_status=ifelse(dup,'failed_validation_duplicate_source_key','unvalidated_provider_export'),raw_record_json=vapply(seq_len(nrow(data)),function(i)as.character(jsonlite::toJSON(as.list(data[i,]),auto_unbox=TRUE,null='null')),character(1)))
  supplementary_schema(con)
  schema<-paste0('declared-export:',digest::digest(list(observational_unit,key_columns,names(data)),algo='sha256'))
  prior<-DBI::dbGetQuery(con,'SELECT schema_id FROM supplementary_snapshots WHERE provider=? AND sha256=?',params=list(provider,sha))
  if(nrow(prior) && any(prior$schema_id!=schema))stop('Existing export grain/key schema differs; do not relabel observations')
  DBI::dbWithTransaction(con,{
    supplementary_append_receipt(con,data.frame(sha256=sha,provider=provider,endpoint='manual_export',request_hash=permission$receipt_id,raw_path=path,received_at=Sys.time(),schema_id=schema,terms_url=permission$terms_url,permission_status='approved_local_retention_other_rights_per_receipt',live_validated=FALSE))
    upsert_rows(con,'supplementary_permission_receipts',data.frame(provider=provider,receipt_id=permission$receipt_id,terms_url=permission$terms_url,local_retention=TRUE,modeling=isTRUE(permission$modeling),derived_publication=isTRUE(permission$derived_publication),raw_redistribution=isTRUE(permission$raw_redistribution),receipt_json=as.character(jsonlite::toJSON(permission,auto_unbox=TRUE,null='null'))),c('provider','receipt_id'))
    upsert_rows(con,'supplementary_export_records',rows,c('snapshot_sha256','source_row'))
  })
  invisible(rows)
}
