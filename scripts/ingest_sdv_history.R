source('scripts/load.R')
args<-commandArgs(trailingOnly=TRUE);years<-if(length(args))as.integer(args) else 1994:2015
con<-connect_warehouse();failed<-character()
tryCatch({
  DBI::dbExecute(con,'SET threads=4');DBI::dbExecute(con,"SET memory_limit='3GB'")
  for(year in years)tryCatch(ingest_sdv_history(con,season_label(year)),error=function(e){message(season_label(year),': ',conditionMessage(e));failed<<-c(failed,season_label(year))})
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
if(length(failed))stop('Incomplete source seasons: ',paste(failed,collapse=', '))
