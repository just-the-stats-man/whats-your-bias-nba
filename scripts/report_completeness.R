source('scripts/load.R')
con<-connect_warehouse()
tryCatch({quarantine_inconsistent_player_totals(con);refresh_inventory(con);refresh_quarantine_diagnostics(con);print(completeness_report(con))},finally=DBI::dbDisconnect(con,shutdown=TRUE))
