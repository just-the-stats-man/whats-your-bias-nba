# A final validation layer separate from source-normalization checkpoints.
# Quarantine only affected game families; keep immutable source bytes and row
# pointers so the exception can be investigated without a whole-history rerun.
historical_quarantine_invalid_games <- function(con) {
  DBI::dbExecute(con,"CREATE TABLE IF NOT EXISTS historical_game_quarantine AS SELECT g.*,'failed_validation' status,'final_score_v1' rule_version,CAST(NULL AS VARCHAR) AS \"rule\" FROM historical_games g WHERE FALSE")
  DBI::dbExecute(con,'CREATE TABLE IF NOT EXISTS historical_quarantine_rows (family VARCHAR,snapshot_id VARCHAR,source_row BIGINT,game_id VARCHAR,rule VARCHAR)')
  bad<-DBI::dbGetQuery(con,'SELECT * FROM historical_games WHERE home_score=away_score')
  if(!nrow(bad))return(invisible(0L))
  DBI::dbWriteTable(con,'_history_bad_games',bad,temporary=TRUE,overwrite=TRUE)
  DBI::dbWithTransaction(con,{
    DBI::dbExecute(con,"INSERT INTO historical_game_quarantine SELECT b.*,'failed_validation','final_score_v1','NBA final scores cannot be tied; source score retained for investigation' FROM _history_bad_games b")
    for(table in c('historical_team_boxes','historical_player_boxes','historical_events','historical_shots')) {
      DBI::dbExecute(con,paste0("INSERT INTO historical_quarantine_rows SELECT '",table,"',snapshot_id,source_row,game_id,'parent game has invalid tied final score' FROM ",table," WHERE game_id IN (SELECT game_id FROM _history_bad_games)"))
      DBI::dbExecute(con,paste0('DELETE FROM ',table,' WHERE game_id IN (SELECT game_id FROM _history_bad_games)'))
    }
    DBI::dbExecute(con,"INSERT INTO historical_exceptions SELECT snapshot_id,source_row,'games',game_id,season,'invalid tied final score; quarantined with raw source preserved' FROM _history_bad_games")
    DBI::dbExecute(con,'DELETE FROM historical_box_checks WHERE game_id IN (SELECT game_id FROM _history_bad_games)')
    DBI::dbExecute(con,'DELETE FROM historical_games WHERE game_id IN (SELECT game_id FROM _history_bad_games)')
  })
  invisible(nrow(bad))
}
