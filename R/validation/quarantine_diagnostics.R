refresh_quarantine_diagnostics <- function(con) {
  inventory<-DBI::dbGetQuery(con,"SELECT i.*,d.revision FROM schedule_inventory i JOIN datasets d ON i.dataset_id=d.dataset_id WHERE i.game_id NOT IN (SELECT game_id FROM games)")
  for(season in unique(inventory$season)) {
    selected<-inventory[inventory$season==season,,drop=FALSE]
    for(revision in unique(selected$revision)) {
      if(!grepl('^[0-9a-f]{40}$',revision))next
      filenames<-paste0(c('nba_schedule','player_box','team_box','play_by_play'),'_',season_end(season),'.parquet')
      if(!all(file.exists(file.path('data/raw',revision,filenames))))next
      bundle<-fetch_season(season,revision)
      x<-normalize_bundle(bundle,season)
      for(id in selected$game_id[selected$revision==revision]) {
        one<-slice_games(x,id);q<-quality_report(one)
        if(nrow(q))upsert_rows(con,'quality_exceptions',exception_rows(id,season,'ingestion',q$check,paste('affected records:',q$count),q$severity,dataset_id=one$games$dataset_id[1]),'exception_id')
      }
    }
  }
  invisible(NULL)
}
