source('scripts/load.R')
con<-connect_warehouse()
tryCatch({refresh_inventory(con);print(completeness_report(con))},finally=DBI::dbDisconnect(con,shutdown=TRUE))
