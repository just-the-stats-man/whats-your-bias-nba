source('scripts/load.R')
args<-commandArgs(trailingOnly=TRUE);years<-if(length(args))as.integer(args) else 1994:2015
con<-connect_warehouse()
tryCatch({
  for(year in years) {
    season<-season_label(year);b<-fetch_sdv_history(season)
    register_sdv_history_raw(con,b,season)
    message(season,': ',paste(vapply(b,function(x)nrow(x$data),integer(1)),collapse='/'),' raw rows cached')
  }
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
