source('scripts/load.R')
args <- commandArgs(trailingOnly=TRUE)
start <- if(length(args)) as.integer(args[1]) else 2016L
end <- if(length(args)>1) as.integer(args[2]) else 2027L
con <- connect_warehouse()
failed <- character()
tryCatch({
  for(year in seq.int(start,end)) {
    season <- season_label(year)
    tryCatch(ingest_season(con,season,revision=Sys.getenv('WYB_ARCHIVE_REVISION',archive_revision)),error=function(e){message(season,': ',conditionMessage(e)); failed <<- c(failed,season)})
  }
  export_parquet(con)
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
if(length(failed)) stop('Incomplete seasons (rerun to resume): ',paste(failed,collapse=', '))
