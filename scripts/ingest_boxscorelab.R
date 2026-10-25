source('scripts/load.R')
args<-commandArgs(trailingOnly=TRUE);con<-connect_warehouse(if(length(args))args[1] else 'data/processed/boxscorelab_stage.duckdb')
tryCatch({ingest_boxscorelab(con);for(t in c('boxscorelab_team_game_results','boxscorelab_team_standings','boxscorelab_player_season_totals')){cat(t,'\n');print(DBI::dbGetQuery(con,paste0('SELECT season,validation_status,count(*) record_count FROM ',t,' GROUP BY season,validation_status ORDER BY season,validation_status')))}},finally=DBI::dbDisconnect(con,shutdown=TRUE))
