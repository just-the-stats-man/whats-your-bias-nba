source('scripts/load.R')
con<-connect_warehouse()
tryCatch({quarantine_inconsistent_player_totals(con);withdraw_quarantined(con);refresh_inventory(con);refresh_quarantine_diagnostics(con);reconcile_game_totals(con);print(completeness_report(con))},finally=DBI::dbDisconnect(con,shutdown=TRUE))
