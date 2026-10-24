warehouse_integrity_report <- function(con) {
  queries<-c(
    possessions_without_game='SELECT count(*) FROM possessions p LEFT JOIN games g USING(game_id) WHERE g.game_id IS NULL',
    lineups_without_game='SELECT count(*) FROM lineups l LEFT JOIN games g USING(game_id) WHERE g.game_id IS NULL',
    lineup_members_without_lineup='SELECT count(*) FROM lineup_players p LEFT JOIN lineups l USING(lineup_id) WHERE l.lineup_id IS NULL',
    pbp_checks_without_game='SELECT count(*) FROM pbp_reconciliation_checks p LEFT JOIN games g USING(game_id) WHERE g.game_id IS NULL',
    lineup_members_without_player='SELECT count(*) FROM lineup_players l LEFT JOIN players p USING(player_id) WHERE p.player_id IS NULL',
    invalid_five='SELECT count(*) FROM (SELECT l.lineup_id FROM lineups l LEFT JOIN lineup_players p USING(lineup_id) GROUP BY l.lineup_id HAVING count(p.player_id)!=5 OR count(DISTINCT p.player_id)!=5)',
    invalid_possession_time='SELECT count(*) FROM possessions WHERE duration_seconds<0 OR start_seconds<0 OR end_seconds<start_seconds OR duration_seconds!=end_seconds-start_seconds',
    invalid_lineup_intervals='SELECT count(*) FROM lineups WHERE duration_seconds<=0 OR start_seconds<0 OR end_seconds<=start_seconds OR duration_seconds!=end_seconds-start_seconds',
    lineup_overlaps='SELECT count(*) FROM (SELECT start_seconds,lag(end_seconds) OVER(PARTITION BY game_id,team_id,period ORDER BY start_seconds) prior_end FROM lineups) WHERE prior_end IS NOT NULL AND prior_end!=start_seconds',
    lineup_time_missing='SELECT count(*) FROM (SELECT game_id,team_id,period,min(start_seconds) first_start,max(end_seconds) final_end,sum(duration_seconds) covered FROM lineups GROUP BY game_id,team_id,period) WHERE first_start!=0 OR final_end!=CASE WHEN period<=4 THEN 720 ELSE 300 END OR covered!=final_end',
    possessions_without_reconciled_status="SELECT count(*) FROM possessions p LEFT JOIN reconstruction_status s USING(game_id) WHERE s.game_id IS NULL OR s.possessions_status!='reconciled'",
    lineups_without_reconciled_status="SELECT count(*) FROM lineups l LEFT JOIN reconstruction_status s USING(game_id) WHERE s.game_id IS NULL OR s.lineups_status!='reconciled'",
    mismatched_published_possession_scores="SELECT count(*) FROM (SELECT game_id,team_id,sum(points) points FROM (SELECT game_id,offense_team_id team_id,points FROM possessions UNION ALL SELECT game_id,team_id,points FROM non_possession_points) GROUP BY game_id,team_id) p JOIN games g USING(game_id) WHERE p.points!=CASE WHEN p.team_id=g.home_team_id THEN g.home_score ELSE g.away_score END",
    invalid_possession_event_links='SELECT count(*) FROM possession_events e LEFT JOIN possessions p USING(possession_id) WHERE e.possession_id IS NOT NULL AND p.possession_id IS NULL',
    contradictory_reference_publication='SELECT count(*) FROM (SELECT game_id FROM possessions UNION SELECT game_id FROM lineups) p WHERE p.game_id IN (SELECT game_id FROM reconciliation_checks WHERE passed IS FALSE)',
    invalid_independent_pbp_benchmark="SELECT count(*) FROM pbp_reconciliation_checks c LEFT JOIN independent_team_totals r ON c.benchmark_dataset_id=r.dataset_id AND c.benchmark_game_id=r.source_game_id AND c.team_id=r.team_id WHERE c.benchmark_type='independent_reference' AND (r.dataset_id IS NULL OR c.metric!='total_turnovers' OR c.box_value IS NOT NULL OR c.benchmark_value IS DISTINCT FROM r.total_turnovers OR EXISTS (SELECT 1 FROM pbp_events e JOIN datasets d ON e.dataset_id=d.dataset_id WHERE e.game_id=c.game_id AND d.source_id=r.source_id))",
    failed_minute_checks_published='SELECT count(*) FROM lineup_minute_checks c WHERE NOT c.passed AND c.game_id IN (SELECT game_id FROM lineups)',
    failed_pbp_metric_published="SELECT count(*) FROM pbp_reconciliation_checks c WHERE (c.passed IS FALSE OR (c.metric!='fg3a' AND c.passed IS NULL)) AND c.game_id IN (SELECT game_id FROM possessions UNION SELECT game_id FROM lineups)",
    invented_defender_observations='SELECT count(*) FROM matchup_observations')
  for(metric in c('fgm','fga','fg3m','fg3a','ftm','fta','assists','turnovers'))queries[paste0('player_team_',metric)]<-sprintf("SELECT count(*) FROM (SELECT p.game_id,p.team_id,sum(CASE WHEN p.did_not_play IS TRUE THEN 0 ELSE p.%1$s END) observed,max(t.%1$s) expected,count(*) FILTER (WHERE p.did_not_play IS DISTINCT FROM TRUE AND p.%1$s IS NULL) unknown_players FROM player_box_scores p JOIN team_box_scores t USING(game_id,team_id) GROUP BY p.game_id,p.team_id) WHERE unknown_players>0 OR observed IS DISTINCT FROM expected",metric)
  result<-data.frame(check=names(queries),violations=vapply(queries,function(q)as.integer(DBI::dbGetQuery(con,q)[[1]][1]),integer(1)))
  result$passed<-result$violations==0L
  result
}

assert_warehouse_integrity <- function(con) {
  report<-warehouse_integrity_report(con)
  if(any(!report$passed))stop('Warehouse integrity failed: ',paste(report$check[!report$passed],collapse=', '))
  invisible(report)
}
