source('scripts/load.R')
args<-commandArgs(trailingOnly=TRUE);years<-if(length(args))as.integer(args) else 1994:2015
con<-connect_warehouse()
tryCatch({
  DBI::dbExecute(con,'SET threads=4');DBI::dbExecute(con,"SET memory_limit='3GB'")
  ingest_sdv_history_parallel(con,season_label(years),workers=as.integer(Sys.getenv('WYB_WORKERS','4')))
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
