source('scripts/load.R')
args<-commandArgs(trailingOnly=TRUE)
seasons<-if(length(args))args else season_label(2016:2027)
con<-connect_warehouse()
tryCatch({
  quarantine_inconsistent_player_totals(con)
  withdraw_quarantined(con)
  import_reference(con)
  recover_reference_boxes(con)
  reconcile_game_totals(con)
  for(season in seasons){reconstruct_season(con,season);gc()}
  assert_warehouse_integrity(con)
  export_parquet(con)
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
