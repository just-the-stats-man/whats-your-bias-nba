reconcile_game_totals_impl <- function(con) {
  # Require a reciprocal home/away pair, a unique date/franchise match, and a
  # single independent game ID. Scores are comparisons, NEVER matching keys.
  DBI::dbExecute(con,'CREATE OR REPLACE TEMP TABLE reference_matches AS
    SELECT g.game_id, r.source_game_id, r.dataset_id
    FROM games g
    JOIN independent_team_totals r ON g.game_date=r.game_date AND g.home_team_id=r.team_id AND g.away_team_id=r.opponent_team_id AND r.home
    JOIN independent_team_totals a ON r.source_id=a.source_id AND r.source_game_id=a.source_game_id AND r.opponent_team_id=a.team_id AND r.team_id=a.opponent_team_id AND NOT a.home
    WHERE r.season=g.season AND a.game_date=r.game_date
    QUALIFY count(*) OVER(PARTITION BY g.game_id)=1 AND count(*) OVER(PARTITION BY r.source_id,r.source_game_id)=1')
  DBI::dbExecute(con,'DELETE FROM reconciliation_checks')
  for(metric in c('points','fgm','fga','fg3m','fg3a','ftm','fta','assists','turnovers')) {
    DBI::dbExecute(con,sprintf("INSERT INTO reconciliation_checks SELECT t.game_id,t.team_id,r.dataset_id,r.source_game_id,'%s',t.%s,r.%s,t.%s-r.%s,CASE WHEN t.%s IS NULL OR r.%s IS NULL THEN NULL ELSE t.%s=r.%s END,(wd.source_id IS NOT NULL AND wd.source_id<>r.source_id) FROM team_box_scores t JOIN reference_matches m USING(game_id) JOIN independent_team_totals r ON r.source_game_id=m.source_game_id AND r.dataset_id=m.dataset_id AND r.team_id=t.team_id LEFT JOIN datasets wd ON wd.dataset_id=t.dataset_id",metric,metric,metric,metric,metric,metric,metric,metric,metric))
  }
  # Reconcile both the schedule and boxes against the reference independently.
  DBI::dbExecute(con,"INSERT INTO reconciliation_checks SELECT g.game_id,r.team_id,r.dataset_id,r.source_game_id,'schedule_points',CASE WHEN r.home THEN g.home_score ELSE g.away_score END,r.points,(CASE WHEN r.home THEN g.home_score ELSE g.away_score END)-r.points,(CASE WHEN r.home THEN g.home_score ELSE g.away_score END)=r.points,TRUE FROM games g JOIN reference_matches m USING(game_id) JOIN independent_team_totals r ON r.source_game_id=m.source_game_id AND r.dataset_id=m.dataset_id")
  resolved<-DBI::dbGetQuery(con,'SELECT g.game_id,g.season,r.team_id,r.source_game_id,r.mapped_player_team_rows,r.dataset_id FROM reference_matches m JOIN games g USING(game_id) JOIN independent_team_totals r ON m.source_game_id=r.source_game_id AND m.dataset_id=r.dataset_id WHERE r.mapped_player_team_rows>0')
  if(nrow(resolved))upsert_rows(con,'quality_exceptions',exception_rows(resolved$game_id,resolved$season,'reference_identity_resolution','missing_team_id_resolved_by_provider_metadata',paste('NBA game',resolved$source_game_id,'team',resolved$team_id,'player rows',resolved$mapped_player_team_rows,'matched uniquely on game/home/team/opponent metadata; statistics unchanged'),severity='warning',dataset_id=resolved$dataset_id),'exception_id')
  mismatches<-DBI::dbGetQuery(con,'SELECT c.*,g.season FROM reconciliation_checks c JOIN games g USING(game_id) WHERE passed IS DISTINCT FROM TRUE')
  if(nrow(mismatches)) upsert_rows(con,'quality_exceptions',exception_rows(mismatches$game_id,mismatches$season,'independent_reconciliation',paste0('reference_',mismatches$metric),paste('team',mismatches$team_id,'warehouse',mismatches$warehouse_value,'reference',mismatches$reference_value),severity=ifelse(is.na(mismatches$passed),'warning','error'),dataset_id=mismatches$reference_dataset_id),'exception_id')
  # Invalidate published reconstructions immediately on an independent
  # contradiction, even before the reconstruction job is rerun.
  # A missing source turnover total may have been checked directly against
  # the reference. Re-evaluate that observed event count on reference refresh.
  DBI::dbExecute(con,"CREATE OR REPLACE TEMP TABLE pbp_reference_updates AS
    WITH providers AS (SELECT e.game_id,min(d.source_id) source_id FROM pbp_events e LEFT JOIN datasets d USING(dataset_id) GROUP BY e.game_id HAVING count(*)=count(d.source_id) AND count(DISTINCT d.source_id)=1)
    SELECT p.game_id,p.team_id,p.metric,p.observed,r.dataset_id,r.source_game_id,
      CASE WHEN r.source_id<>providers.source_id THEN r.total_turnovers ELSE NULL END expected
    FROM pbp_reconciliation_checks p LEFT JOIN reference_matches m USING(game_id)
    LEFT JOIN independent_team_totals r ON m.dataset_id=r.dataset_id AND m.source_game_id=r.source_game_id AND p.team_id=r.team_id
    LEFT JOIN providers ON p.game_id=providers.game_id
    WHERE p.metric='total_turnovers' AND p.box_value IS NULL")
  DBI::dbExecute(con,"UPDATE pbp_reconciliation_checks p SET benchmark_value=u.expected,benchmark_dataset_id=u.dataset_id,benchmark_game_id=u.source_game_id,benchmark_type=CASE WHEN u.expected IS NULL THEN 'unavailable' ELSE 'independent_reference' END,difference=p.observed-u.expected,passed=CASE WHEN p.observed IS NULL OR u.expected IS NULL THEN NULL ELSE p.observed=u.expected END,status=CASE WHEN p.observed IS NULL OR u.expected IS NULL THEN 'unavailable' WHEN p.observed=u.expected THEN 'match' ELSE 'mismatch' END FROM pbp_reference_updates u WHERE p.game_id=u.game_id AND p.team_id=u.team_id AND p.metric=u.metric")
  DBI::dbExecute(con,"CREATE OR REPLACE TEMP TABLE reference_conflicts AS SELECT DISTINCT game_id FROM reconciliation_checks WHERE passed IS FALSE UNION SELECT DISTINCT game_id FROM pbp_reconciliation_checks WHERE metric='total_turnovers' AND box_value IS NULL AND passed IS DISTINCT FROM TRUE")
  DBI::dbExecute(con,'DELETE FROM lineup_players WHERE lineup_id IN (SELECT lineup_id FROM lineups WHERE game_id IN (SELECT game_id FROM reference_conflicts))')
  for(table in c('lineups','possessions','possession_events','non_possession_points'))DBI::dbExecute(con,paste('DELETE FROM',table,'WHERE game_id IN (SELECT game_id FROM reference_conflicts)'))
  DBI::dbExecute(con,"UPDATE reconstruction_status SET possessions_status='unresolved_reference',lineups_status='unresolved_reference' WHERE game_id IN (SELECT game_id FROM reference_conflicts)")
  DBI::dbRemoveTable(con,'reference_conflicts')
  DBI::dbRemoveTable(con,'pbp_reference_updates')
  DBI::dbRemoveTable(con,'reference_matches')
  invisible(mismatches)
}

reconcile_game_totals <- function(con) DBI::dbWithTransaction(con,reconcile_game_totals_impl(con))
