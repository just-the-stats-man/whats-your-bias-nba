source('scripts/load.R')
input<-phase3_snapshot_connection();stage<-connect_warehouse('data/processed/phase3/shot_stage.duckdb')
tryCatch({
  DBI::dbExecute(stage,'SET threads=4');DBI::dbExecute(stage,"SET memory_limit='2GB'")
  args<-commandArgs(trailingOnly=TRUE)
  seasons<-if(length(args))season_label(as.integer(args)) else DBI::dbGetQuery(input,'SELECT DISTINCT season FROM pbp_events JOIN games USING(game_id) ORDER BY season')$season
  for(season in seasons)stage_shot_recovery(input,stage,season)
},finally={DBI::dbDisconnect(stage,shutdown=TRUE);DBI::dbDisconnect(input,shutdown=TRUE)})
