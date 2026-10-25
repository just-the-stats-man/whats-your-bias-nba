source('scripts/load.R')
con<-connect_warehouse('data/processed/boxscorelab_stage.duckdb')
tryCatch({
  for(t in c('historical_games','historical_team_boxes'))DBI::dbExecute(con,paste0('CREATE OR REPLACE VIEW ',t,' AS SELECT * FROM read_parquet(',DBI::dbQuoteString(con,normalizePath(file.path('data/processed/historical_parquet',paste0(t,'.parquet')),winslash='/')),')'))
  print(boxscorelab_reports(con))
  print(DBI::dbGetQuery(con,"SELECT season,game_date,team,opponent,points,opponent_points,rebounds,offensive_rebounds,defensive_rebounds FROM boxscorelab_team_game_results WHERE validation_status!='observed'"))
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
