source('scripts/load.R')
args<-commandArgs(trailingOnly=TRUE)
years<-if(length(args))as.integer(args) else 2004L
if(anyNA(years) || any(years<2002L | years>2015L))stop('Select SDV PBP season end years 2002 through 2015')
seasons<-season_label(sort(unique(years)))
con<-connect_warehouse()
tryCatch({
  DBI::dbExecute(con,'SET threads=4')
  DBI::dbExecute(con,"SET memory_limit='3GB'")
  DBI::dbExecute(con,'CREATE TABLE IF NOT EXISTS historical_sdv_checkpoints (season VARCHAR PRIMARY KEY, revision VARCHAR, transform_id VARCHAR, completed_at TIMESTAMP)')
  import_historical_reference(con,seasons)
  transform<-digest::digest(list(reconstruction_version,body(audit_ingest_season),body(quality_report)),algo='sha256')
  preserved_players<-DBI::dbReadTable(con,'players')
  for(season in seasons) {
    done<-DBI::dbGetQuery(con,'SELECT * FROM historical_sdv_checkpoints WHERE season=? AND revision=? AND transform_id=?',params=list(season,archive_revision,transform))
    if(nrow(done))next
    tryCatch(audit_ingest_season(con,season),finally={
      # Ingesting older rosters must not replace current recorded player names.
      upsert_rows(con,'players',preserved_players,'player_id')
    })
    upsert_rows(con,'historical_sdv_checkpoints',data.frame(season=season,revision=archive_revision,transform_id=transform,completed_at=Sys.time()),'season')
  }
  reconcile_game_totals(con)
  for(season in seasons)reconstruct_season(con,season,batch_size=100L)
  assert_warehouse_integrity(con)
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
