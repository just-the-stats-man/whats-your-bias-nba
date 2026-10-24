source('scripts/load.R')
con <- connect_warehouse()
tryCatch({ingest_bundle(con,readRDS('data/sample/bundle.rds'),'2024-25');export_parquet(con)},finally=DBI::dbDisconnect(con,shutdown=TRUE))
