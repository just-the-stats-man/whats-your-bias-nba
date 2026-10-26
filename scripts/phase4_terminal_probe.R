source('scripts/load.R');con<-DBI::dbConnect(duckdb::duckdb(),dbdir='data/processed/phase4/baseline.duckdb',read_only=TRUE)
tryCatch({
  print(DBI::dbGetQuery(con,"SELECT e.event_type,e.description,count(*) n FROM historical_events e WHERE e.season='2023-24' AND (lower(description) LIKE '%game end%' OR lower(description) LIKE '%end of game%') GROUP BY ALL ORDER BY n DESC LIMIT 12"))
  ids<-DBI::dbGetQuery(con,"SELECT DISTINCT game_id FROM historical_event_checks WHERE season='2023-24' AND metric='points' AND status='failed_validation' ORDER BY game_id LIMIT 3")$game_id
  for(id in ids) {
    print(DBI::dbGetQuery(con,"SELECT e.*,g.home_score box_home,g.away_score box_away FROM historical_events e JOIN historical_games g USING(game_id) WHERE e.game_id=? ORDER BY TRY_CAST(event_id AS BIGINT) DESC LIMIT 5",params=list(id)))
    print(DBI::dbGetQuery(con,'SELECT * FROM historical_events WHERE game_id=? ORDER BY source_row DESC LIMIT 4',params=list(id)))
  }
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
