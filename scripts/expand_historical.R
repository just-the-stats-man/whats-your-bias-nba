source('scripts/load.R')
args<-commandArgs(trailingOnly=TRUE)
mode<-if(length(args))args[1] else 'boxes'
seasons<-if(length(args)>1)season_label(as.integer(args[-1])) else NULL
con<-connect_warehouse()
tryCatch({
  DBI::dbExecute(con,'SET threads=4')
  DBI::dbExecute(con,"SET memory_limit='3GB'")
  if(mode=='boxes') {
    ingest_historical_boxes(con,seasons=seasons)
    ingest_historical_identities(con)
  }
  else if(mode=='events')ingest_historical_events(con,seasons=seasons)
  else stop('Choose boxes or events; subsequent arguments are season end years')
  historical_quarantine_invalid_games(con)
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
