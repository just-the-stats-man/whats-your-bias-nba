# Apply the same aggregate gate to warehouses created before it was added.
# The source records are retained in raw files and their dataset manifests.
quarantine_inconsistent_player_totals <- function(con) {
  findings<-list()
  for(metric in c('fgm','fga','fg3m','fg3a','ftm','fta','assists','turnovers')) {
    sql<-sprintf("SELECT p.game_id,p.team_id,g.season,max(p.dataset_id) dataset_id,
      sum(CASE WHEN p.did_not_play IS TRUE THEN 0 ELSE p.%1$s END) player_sum,
      max(t.%1$s) team_value,
      count(*) FILTER (WHERE p.did_not_play IS DISTINCT FROM TRUE AND p.%1$s IS NULL) unknown_players
      FROM player_box_scores p JOIN team_box_scores t USING(game_id,team_id)
      JOIN games g USING(game_id) GROUP BY p.game_id,p.team_id,g.season
      HAVING unknown_players>0 OR max(t.%1$s) IS NULL OR player_sum!=max(t.%1$s)",metric)
    d<-DBI::dbGetQuery(con,sql)
    if(nrow(d)) {
      d$metric<-metric;findings[[length(findings)+1L]]<-d
    }
  }
  if(!length(findings))return(invisible(data.frame()))
  d<-do.call(rbind,findings)
  unavailable<-d$unknown_players>0 | is.na(d$team_value)
  rules<-paste('player',d$metric,ifelse(unavailable,'unavailable for team reconciliation','differs from team total'))
  exceptions<-exception_rows(d$game_id,d$season,'ingestion',rules,paste('team',d$team_id,'player sum',d$player_sum,'team value',d$team_value,'unknown players',d$unknown_players),dataset_id=d$dataset_id)
  DBI::dbWithTransaction(con,{
    upsert_rows(con,'quality_exceptions',exceptions,'exception_id')
    for(id in unique(d$game_id))DBI::dbExecute(con,"UPDATE schedule_inventory SET validation_status='quarantined' WHERE game_id=?",params=list(id))
  })
  # Include legacy games with no schedule_inventory row in withdrawal too.
  withdraw_quarantined(con,additional_ids=unique(d$game_id))
  message('Quarantined ',length(unique(d$game_id)),' games with inconsistent or unavailable player/team aggregates')
  invisible(d)
}
