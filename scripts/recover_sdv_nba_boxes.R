source('scripts/load.R');args<-commandArgs(trailingOnly=TRUE)
seasons<-season_label(if(length(args))as.integer(args) else 2002:2015)
con<-connect_warehouse()
tryCatch({DBI::dbExecute(con,'SET threads=4');recover_sdv_nba_boxes(con,seasons)},finally=DBI::dbDisconnect(con,shutdown=TRUE))
