warehouse_integrity_report <- function(con) {
  queries<-c(
    possessions_without_game='SELECT count(*) FROM possessions p LEFT JOIN games g USING(game_id) WHERE g.game_id IS NULL',
    lineup_members_without_player='SELECT count(*) FROM lineup_players l LEFT JOIN players p USING(player_id) WHERE p.player_id IS NULL',
    invalid_five='SELECT count(*) FROM (SELECT l.lineup_id FROM lineups l LEFT JOIN lineup_players p USING(lineup_id) GROUP BY l.lineup_id HAVING count(p.player_id)!=5 OR count(DISTINCT p.player_id)!=5)',
    invalid_possession_time='SELECT count(*) FROM possessions WHERE duration_seconds<0 OR start_seconds<0 OR end_seconds<start_seconds OR duration_seconds!=end_seconds-start_seconds',
    invalid_lineup_intervals='SELECT count(*) FROM lineups WHERE duration_seconds<=0 OR start_seconds<0 OR end_seconds<=start_seconds OR duration_seconds!=end_seconds-start_seconds',
    lineup_overlaps='SELECT count(*) FROM (SELECT start_seconds,lag(end_seconds) OVER(PARTITION BY game_id,team_id,period ORDER BY start_seconds) prior_end FROM lineups) WHERE prior_end IS NOT NULL AND prior_end!=start_seconds',
    lineup_time_missing='SELECT count(*) FROM (SELECT game_id,team_id,period,min(start_seconds) first_start,max(end_seconds) final_end,sum(duration_seconds) covered FROM lineups GROUP BY game_id,team_id,period) WHERE first_start!=0 OR final_end!=CASE WHEN period<=4 THEN 720 ELSE 300 END OR covered!=final_end',
    possessions_without_reconciled_status="SELECT count(*) FROM possessions p JOIN reconstruction_status s USING(game_id) WHERE s.possessions_status!='reconciled'",
    lineups_without_reconciled_status="SELECT count(*) FROM lineups l JOIN reconstruction_status s USING(game_id) WHERE s.lineups_status!='reconciled'",
    mismatched_published_possession_scores="SELECT count(*) FROM (SELECT game_id,team_id,sum(points) points FROM (SELECT game_id,offense_team_id team_id,points FROM possessions UNION ALL SELECT game_id,team_id,points FROM non_possession_points) GROUP BY game_id,team_id) p JOIN games g USING(game_id) WHERE p.points!=CASE WHEN p.team_id=g.home_team_id THEN g.home_score ELSE g.away_score END",
    invalid_possession_event_links='SELECT count(*) FROM possession_events e LEFT JOIN possessions p USING(possession_id) WHERE e.possession_id IS NOT NULL AND p.possession_id IS NULL',
    contradictory_reference_publication='SELECT count(*) FROM possessions p WHERE p.game_id IN (SELECT game_id FROM reconciliation_checks WHERE passed IS DISTINCT FROM TRUE)',
    failed_minute_checks_published='SELECT count(*) FROM lineup_minute_checks c WHERE NOT c.passed AND c.game_id IN (SELECT game_id FROM lineups)',
    invented_defender_observations='SELECT count(*) FROM matchup_observations')
  result<-data.frame(check=names(queries),violations=vapply(queries,function(q)as.integer(DBI::dbGetQuery(con,q)[[1]][1]),integer(1)))
  result$passed<-result$violations==0L
  result
}

assert_warehouse_integrity <- function(con) {
  report<-warehouse_integrity_report(con)
  if(any(!report$passed))stop('Warehouse integrity failed: ',paste(report$check[!report$passed],collapse=', '))
  invisible(report)
}
