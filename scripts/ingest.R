source('scripts/load.R')
args <- commandArgs(trailingOnly=TRUE)
seasons <- if(length(args)) args else '2024-25'
con <- connect_warehouse()
tryCatch({
  for(season in seasons) ingest_season(con,season)
  export_parquet(con)
}, finally=DBI::dbDisconnect(con,shutdown=TRUE))
