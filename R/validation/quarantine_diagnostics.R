refresh_quarantine_diagnostics <- function(con,recover=FALSE,seasons=NULL) {
  recovered<-character()
  inventory<-DBI::dbGetQuery(con,"SELECT i.*,d.revision FROM schedule_inventory i JOIN datasets d ON i.dataset_id=d.dataset_id WHERE i.game_id NOT IN (SELECT game_id FROM games)")
  if(!is.null(seasons))inventory<-inventory[inventory$season%in%seasons,,drop=FALSE]
  for(season in unique(inventory$season)) {
    selected<-inventory[inventory$season==season,,drop=FALSE]
    for(revision in unique(selected$revision)) {
      if(!grepl('^[0-9a-f]{40}$',revision))next
      filenames<-paste0(c('nba_schedule','player_box','team_box','play_by_play'),'_',season_end(season),'.parquet')
      if(!all(file.exists(file.path('data/raw',revision,filenames))))next
      bundle<-fetch_season(season,revision)
      ids<-selected$game_id[selected$revision==revision]
      bundle<-lapply(bundle,function(z){z$sha256<-file_sha256(z$path);z})
      x<-normalize_bundle(bundle,season,game_ids=ids)
      notes<-attr(x,'normalization_notes')
      for(id in selected$game_id[selected$revision==revision]) {
        one<-slice_games(x,id);q<-quality_report(one)
        if(nrow(q))upsert_rows(con,'quality_exceptions',exception_rows(id,season,'ingestion',q$check,paste('affected records:',q$count),q$severity,dataset_id=one$games$dataset_id[1]),'exception_id')
        if(recover && !any(q$severity=='error')) {
          ingest_bundle(con,bundle,season,normalized=one,validated_report=q)
          DBI::dbExecute(con,"UPDATE schedule_inventory SET validation_status='passed' WHERE game_id=?",params=list(id))
          if(!is.null(notes) && nrow(notes)) {
            n<-notes[notes$game_id==id,,drop=FALSE]
            if(nrow(n))upsert_rows(con,'quality_exceptions',exception_rows(n$game_id,season,'normalization',n$rule,n$detail,severity='warning',dataset_id=n$dataset_id),'exception_id')
          }
          upsert_rows(con,'quality_exceptions',exception_rows(id,season,'normalization','quarantine_revalidated_current_gate','Original cached records pass the current quality gate; prior failures retained; reconstructions require separate validation',severity='warning',dataset_id=one$games$dataset_id[1]),'exception_id')
          recovered<-c(recovered,id)
        }
      }
    }
  }
  invisible(recovered)
}
