source('scripts/load.R')
con<-connect_warehouse()
failures<-character()
tryCatch({
  args<-commandArgs(trailingOnly=TRUE)
  years<-if(length(args)) as.integer(args) else 2016:2027
  for(year in years) {
    tryCatch(audit_ingest_season(con,season_label(year)),error=function(e){message(season_label(year),': ',conditionMessage(e));failures<<-c(failures,season_label(year))})
    gc()
  }
  export_parquet(con)
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
if(length(failures))stop('Unprocessed seasons: ',paste(failures,collapse=', '))
