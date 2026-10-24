source('scripts/load.R')
targets::tar_option_set(packages=c('DBI','duckdb','arrow','dplyr','dbplyr','httr2'))
list(targets::tar_target(sample_file,'data/sample/bundle.rds',format='file'),
     targets::tar_target(reference_file,'data/sample/independent_team_totals.csv',format='file'),
     targets::tar_target(sample_bundle,readRDS(sample_file)),
     targets::tar_target(warehouse,{
       con <- connect_warehouse()
       tryCatch({
         ingest_bundle(con,sample_bundle,'2024-25')
         import_reference(con,load_reference_fixture(reference_file));reconcile_game_totals(con)
         reconstruct_season(con,'2024-25');assert_warehouse_integrity(con)
         export_parquet(con)
       },finally=DBI::dbDisconnect(con,shutdown=TRUE))
       'data/processed/nba.duckdb'
     },format='file'))
