source('scripts/load.R');con<-DBI::dbConnect(duckdb::duckdb(),dbdir='data/processed/phase4/baseline.duckdb',read_only=TRUE)
tryCatch({
  DBI::dbExecute(con,'SET threads=4');DBI::dbExecute(con,"SET memory_limit='3GB'")
  print(DBI::dbListFields(con,'sdv_nba_player_links'));print(utils::head(DBI::dbReadTable(con,'sdv_nba_player_links'),2))
  print(DBI::dbGetQuery(con,"SELECT metric,status,count(*) checks FROM historical_event_checks WHERE season='2023-24' GROUP BY ALL"))
  reference<-shot_reference_observations(con,'2023-24');saveRDS(reference,'data/processed/phase4/reference_original_2024.rds')
  e<-DBI::dbGetQuery(con,"SELECT e.* FROM pbp_events e JOIN games g USING(game_id) WHERE g.season='2023-24' ORDER BY e.game_id,e.event_order")
  c<-DBI::dbGetQuery(con,"SELECT * FROM shot_recovery_candidates WHERE season='2023-24'")
  missing<-c[is.na(c$points_attempted)&c$game_id%in%e$game_id,]
  saveRDS(list(events=e,candidates=c,missing=missing),'data/processed/phase4/shot_pilot_inputs_2024.rds')
  print(table(missing$player_id)[order(table(missing$player_id),decreasing=TRUE)][1:15])
  print(DBI::dbGetQuery(con,"SELECT p.player_id,n.name,count(*) games FROM player_box_scores p JOIN games g USING(game_id) JOIN players n USING(player_id) WHERE g.season='2023-24' AND p.player_id IN (SELECT player_id FROM shot_recovery_candidates WHERE season='2023-24' AND points_attempted IS NULL) GROUP BY ALL ORDER BY games DESC LIMIT 10"))
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
