source('scripts/load.R')
args<-commandArgs(trailingOnly=TRUE)
path<-if(length(args))args[1] else 'data/processed/tracking_stage.duckdb'
con<-connect_warehouse(path)
tryCatch({ingest_tracking_features(con);print(DBI::dbGetQuery(con,'SELECT season,validation_status,count(*) record_count,count(DISTINCT game_id) games FROM tracking_provider_context GROUP BY season,validation_status'));print(DBI::dbGetQuery(con,'SELECT metric,status,count(*) record_count FROM tracking_provider_estimates GROUP BY metric,status ORDER BY metric,status'))},finally=DBI::dbDisconnect(con,shutdown=TRUE))
