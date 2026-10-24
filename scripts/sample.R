source('scripts/load.R')
con <- connect_warehouse()
tryCatch({
  ingest_bundle(con,readRDS('data/sample/bundle.rds'),'2024-25')
  import_reference(con,load_reference_fixture());reconcile_game_totals(con)
  reconstruct_season(con,'2024-25');assert_warehouse_integrity(con)
  export_parquet(con)
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
