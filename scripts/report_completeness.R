source('scripts/load.R')
con<-connect_warehouse()
tryCatch({refresh_inventory(con);refresh_quarantine_diagnostics(con);print(completeness_report(con))},finally=DBI::dbDisconnect(con,shutdown=TRUE))
