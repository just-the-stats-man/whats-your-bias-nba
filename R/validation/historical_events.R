# These are within-upstream consistency checks, not independent measurements.
# They validate recorded shot counts and last reported score, not possessions,
# substitution completeness, free throws or turnover definitions.
historical_event_checks <- function(con) {
  DBI::dbExecute(con,"CREATE OR REPLACE TEMP TABLE _history_shot_counts AS SELECT game_id,team_id,count(*) fga,count(*) FILTER (WHERE made IS TRUE) fgm,count(*) FILTER (WHERE points_attempted=3) fg3a,count(*) FILTER (WHERE points_attempted=3 AND made IS TRUE) fg3m,count(*) FILTER (WHERE made IS NULL) unknown_result,count(*) FILTER (WHERE points_status!='observed') unknown_value FROM historical_shots GROUP BY game_id,team_id")
  DBI::dbExecute(con,"CREATE OR REPLACE TEMP TABLE _history_shot_flags AS SELECT s.game_id,bool_or(s.team_id IS NULL OR s.team_id NOT IN (g.home_team_id,g.away_team_id)) unknown_team FROM historical_shots s JOIN historical_games g USING(game_id) GROUP BY s.game_id")
  DBI::dbExecute(con,"CREATE OR REPLACE TEMP TABLE _history_last_score AS SELECT game_id,arg_max(home_score,TRY_CAST(event_id AS BIGINT)) final_home,arg_max(away_score,TRY_CAST(event_id AS BIGINT)) final_away FROM historical_events WHERE home_score>0 AND away_score>0 AND TRY_CAST(event_id AS BIGINT)>0 GROUP BY game_id")
  DBI::dbExecute(con,'CREATE OR REPLACE TEMP TABLE _history_event_games AS SELECT DISTINCT game_id FROM historical_events')
  DBI::dbExecute(con,'CREATE OR REPLACE TABLE historical_event_checks (game_id VARCHAR,season VARCHAR,team_id VARCHAR,metric VARCHAR,event_value DOUBLE,box_value DOUBLE,status VARCHAR,independent BOOLEAN)')
  for(m in c('points','fgm','fga','fg3m','fg3a')) {
    obs<-switch(m,points='CASE WHEN t.team_id=g.home_team_id THEN f.final_home ELSE f.final_away END',
      fga='CASE WHEN flags.unknown_team IS FALSE THEN s.fga END',
      fgm='CASE WHEN flags.unknown_team IS FALSE AND s.unknown_result=0 THEN s.fgm END',
      fg3a='CASE WHEN flags.unknown_team IS FALSE AND s.unknown_value=0 THEN s.fg3a END',
      fg3m='CASE WHEN flags.unknown_team IS FALSE AND s.unknown_value=0 AND s.unknown_result=0 THEN s.fg3m END')
    DBI::dbExecute(con,paste0("INSERT INTO historical_event_checks WITH b AS (SELECT t.game_id,t.season,t.team_id,'",m,"' metric,",obs," event_value,CASE WHEN t.",m,"_status='observed' AND t.validation_status='observed' THEN t.",m," END box_value FROM historical_team_boxes t JOIN _history_event_games e USING(game_id) JOIN historical_games g USING(game_id) LEFT JOIN _history_shot_counts s ON s.game_id=t.game_id AND s.team_id=t.team_id LEFT JOIN _history_last_score f ON f.game_id=t.game_id LEFT JOIN _history_shot_flags flags ON flags.game_id=t.game_id) SELECT *,CASE WHEN event_value IS NULL OR box_value IS NULL THEN 'source_missing' WHEN event_value=box_value THEN 'reconstructed' ELSE 'failed_validation' END,FALSE FROM b"))
  }
  invisible(NULL)
}

historical_family_matrix <- function(con,report) {
  rows<-lapply(seq_len(nrow(report)),function(i) {
    r<-report[i,]
    families<-c('team_boxes','player_boxes','pbp','shots','shot_coordinates','possessions','lineups','tracking','official_season_totals')
    counts<-c(r$team_rows,r$player_rows,r$event_rows,r$shot_rows,r$coordinate_rows,r$possession_rows,r$lineup_rows,0,0)
    status<-ifelse(counts>0,'observed','source_missing')
    status[6:7]<-ifelse(counts[6:7]>0,'reconstructed','source_missing')
    status[8]<-if(substr(r$season,1,4)>='2013')'not_licensed' else 'source_missing'
    data.frame(season=r$season,family=families,rows=counts,status=status,
      limitation=c('metric-specific availability; raw scoring exceptions retained','recorded rows include DNP/unknown appearances; not games played','recorded event availability does not establish complete order or possessions','made/value fields can be unavailable','raw provider coordinates; plausibility screen only','strict canonical reconstruction gates','strict membership and minute gates','no authorized tracking export; earlier availability unverified','only partial covered-game sums are implemented'))
  })
  do.call(rbind,rows)
}
