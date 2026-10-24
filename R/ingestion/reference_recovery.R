recover_reference_boxes <- function(con) {
  candidates<-DBI::dbGetQuery(con,"SELECT DISTINCT i.* FROM schedule_inventory i JOIN quality_exceptions q USING(game_id) WHERE i.validation_status='quarantined' AND q.stage='ingestion' AND (q.rule IN ('missing team box scores','team_box_scores inconsistent scoring totals','player points differ from team total','team points differ from schedule') OR q.rule LIKE 'player % differs from team total')")
  recovered<-character()
  for(season in unique(candidates$season)) {
    bundle<-fetch_season(season)
    bundle<-lapply(bundle,function(z){z$sha256<-file_sha256(z$path);z})
    games<-candidates[candidates$season==season,,drop=FALSE]
    x<-normalize_bundle(bundle,season,game_ids=games$game_id)
    for(i in seq_len(nrow(games))) {
      g<-games[i,,drop=FALSE]
      home<-DBI::dbGetQuery(con,'SELECT * FROM independent_team_totals WHERE season=? AND game_date=? AND team_id=? AND opponent_team_id=? AND home',params=list(season,g$game_date,g$home_team_id,g$away_team_id))
      if(nrow(home)!=1L)next
      ref<-DBI::dbGetQuery(con,'SELECT * FROM independent_team_totals WHERE source_id=? AND source_game_id=?',params=list(home$source_id,home$source_game_id))
      if(nrow(ref)!=2L || !setequal(ref$team_id,c(g$home_team_id,g$away_team_id)))next
      one<-slice_games(x,g$game_id)
      if(nrow(one$games)!=1L)next
      # Replace the WHOLE team record with an attributed alternative provider,
      # never patch individual cells to force a score identity to pass.
      tb<-ref[c('team_id','points','fgm','fga','fg3m','fg3a','ftm','fta','assists','turnovers','dataset_id','total_turnovers')]
      tb$game_id<-g$game_id;one$team_box_scores<-tb
      q<-tryCatch(quality_report(one),error=function(e)data.frame(severity='error'))
      if(any(q$severity=='error'))next
      ingest_bundle(con,bundle,season,normalized=one,validated_report=q)
      DBI::dbExecute(con,"UPDATE schedule_inventory SET validation_status='passed_reference_box' WHERE game_id=?",params=list(g$game_id))
      upsert_rows(con,'quality_exceptions',exception_rows(g$game_id,season,'reference_recovery','whole_team_box_from_alternative_provider',paste('NBA-derived team rows from',home$source_game_id,'replace invalid/missing ESPN team rows; self-comparisons flagged independent=FALSE'),severity='warning',dataset_id=home$dataset_id),'exception_id')
      recovered<-c(recovered,g$game_id)
    }
  }
  message('Recovered ',length(recovered),' games using attributed alternative team boxes')
  invisible(recovered)
}
