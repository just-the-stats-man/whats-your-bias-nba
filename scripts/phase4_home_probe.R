source('scripts/load.R');con<-DBI::dbConnect(duckdb::duckdb(),dbdir=':memory:')
tryCatch({
  p<-'data/raw/independent/PlayerStatistics_v524.csv'
  print(DBI::dbGetQuery(con,paste0("SELECT gameId,personId,home,playerteamId,opponentteamId,points,fieldGoalsMade,threePointersMade,freeThrowsMade FROM read_csv(",DBI::dbQuoteString(con,p),",all_varchar=TRUE) WHERE TRY_CAST(gameId AS BIGINT)=22101212 LIMIT 8")))
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
