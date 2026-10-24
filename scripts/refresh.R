source('scripts/load.R')
con <- connect_warehouse()
tryCatch({
  # Mutable main: conditional ETags avoid unchanged downloads. Refresh replaces
  # selected fact snapshots so upstream corrections are not silently ignored.
  ingest_season(con,Sys.getenv('WYB_SEASON','2026-27'),revision='main',refresh=TRUE)
  export_parquet(con)
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
