withdraw_quarantined <- function(con,additional_ids=character()) {
  stale<-DBI::dbGetQuery(con,"SELECT g.game_id,g.season,g.dataset_id FROM games g JOIN schedule_inventory i USING(game_id) WHERE i.validation_status='quarantined'")
  if(length(additional_ids)) {
    extra<-DBI::dbGetQuery(con,paste0('SELECT game_id,season,dataset_id FROM games WHERE game_id IN (',paste(DBI::dbQuoteString(con,additional_ids),collapse=','),')'))
    stale<-unique(rbind(stale,extra))
  }
  # Older withdrawal versions retained these derived diagnostics after the
  # canonical game was removed. Detailed exception history remains separate.
  DBI::dbExecute(con,'DELETE FROM pbp_reconciliation_checks WHERE game_id NOT IN (SELECT game_id FROM games)')
  if(!nrow(stale))return(invisible(0L))
  DBI::dbWithTransaction(con,{
    DBI::dbWriteTable(con,'_withdraw',stale['game_id'],temporary=TRUE,overwrite=TRUE)
    DBI::dbExecute(con,'DELETE FROM lineup_players WHERE lineup_id IN (SELECT lineup_id FROM lineups WHERE game_id IN (SELECT game_id FROM _withdraw))')
    for(table in c('lineups','possessions','possession_events','non_possession_points','lineup_minute_checks','reconstruction_status','reconciliation_checks','pbp_reconciliation_checks','player_box_scores','team_box_scores','pbp_events','shot_attempts','substitutions','games'))DBI::dbExecute(con,paste('DELETE FROM',table,'WHERE game_id IN (SELECT game_id FROM _withdraw)'))
    upsert_rows(con,'quality_exceptions',exception_rows(stale$game_id,stale$season,'validation_migration','withdraw_superseded_canonical_snapshot','A previously loaded game fails the current audited gate; raw data and provenance retained',severity='warning',dataset_id=stale$dataset_id),'exception_id')
    DBI::dbRemoveTable(con,'_withdraw')
  })
  message('Withdrew ',nrow(stale),' superseded canonical games pending validated recovery')
  invisible(nrow(stale))
}
