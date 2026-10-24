source('scripts/load.R')
targets::tar_option_set(packages=c('DBI','duckdb','arrow','dplyr','dbplyr','httr2'))
list(targets::tar_target(sample_bundle,readRDS('data/sample/bundle.rds')),
     targets::tar_target(warehouse,{
       con <- connect_warehouse()
       tryCatch({ingest_bundle(con,sample_bundle,'2024-25'); export_parquet(con)},finally=DBI::dbDisconnect(con,shutdown=TRUE))
       'data/processed/nba.duckdb'
     },format='file'))
