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
  mismatches<-DBI::dbGetQuery(con,'SELECT c.*,g.season FROM reconciliation_checks c JOIN games g USING(game_id) WHERE passed IS DISTINCT FROM TRUE')
  if(nrow(mismatches)) upsert_rows(con,'quality_exceptions',exception_rows(mismatches$game_id,mismatches$season,'independent_reconciliation',paste0('reference_',mismatches$metric),paste('team',mismatches$team_id,'warehouse',mismatches$warehouse_value,'reference',mismatches$reference_value),dataset_id=mismatches$reference_dataset_id),'exception_id')
  # Invalidate published reconstructions immediately on an independent
  # contradiction, even before the reconstruction job is rerun.
  DBI::dbExecute(con,'CREATE OR REPLACE TEMP TABLE reference_conflicts AS SELECT DISTINCT game_id FROM reconciliation_checks WHERE passed IS DISTINCT FROM TRUE')
  DBI::dbExecute(con,'DELETE FROM lineup_players WHERE lineup_id IN (SELECT lineup_id FROM lineups WHERE game_id IN (SELECT game_id FROM reference_conflicts))')
  for(table in c('lineups','possessions','possession_events','non_possession_points'))DBI::dbExecute(con,paste('DELETE FROM',table,'WHERE game_id IN (SELECT game_id FROM reference_conflicts)'))
  DBI::dbExecute(con,"UPDATE reconstruction_status SET possessions_status='unresolved_reference',lineups_status='unresolved_reference' WHERE game_id IN (SELECT game_id FROM reference_conflicts)")
  DBI::dbRemoveTable(con,'reference_conflicts')
  DBI::dbRemoveTable(con,'reference_matches')
  invisible(mismatches)
}

reconcile_game_totals <- function(con) DBI::dbWithTransaction(con,reconcile_game_totals_impl(con))
