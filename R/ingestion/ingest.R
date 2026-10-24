ingest_bundle <- function(con, bundle, season, game_ids=NULL) {
  run <- paste0('run:', format(Sys.time(),'%Y%m%d%H%M%OS6'),':',sample.int(1e9,1))
  DBI::dbExecute(con,"INSERT OR IGNORE INTO sources VALUES ('sportsdataverse','https://github.com/sportsdataverse/hoopR-nba-data','CC-BY-4.0','hoopR.nba authors; ESPN upstream; normalized by Whats Your Bias')")
  DBI::dbExecute(con,'INSERT INTO ingestion_runs VALUES (?, ?, ?, ?, NULL, ?, NULL)',params=list(run,'sportsdataverse',season,Sys.time(),'running'))
  tryCatch({
    x <- normalize_bundle(bundle,season,game_ids)
    if (!nrow(x$games)) stop('No completed regular-season or playoff games selected')
    report <- quality_report(x)
    dir.create('data/processed/quality',recursive=TRUE,showWarnings=FALSE)
    utils::write.csv(report,file.path('data/processed/quality',paste0(gsub(':','-',run),'.csv')),row.names=FALSE)
    assert_quality(x)
    datasets <- do.call(rbind,lapply(names(bundle),function(kind) {
      z <- bundle[[kind]]; hash <- file_sha256(z$path)
      data.frame(dataset_id=paste0('sdv:',kind,':',season,':',hash),source_id='sportsdataverse',url=z$url,revision=z$revision,retrieved_at=Sys.time(),sha256=hash,raw_path=z$path,row_count=nrow(z$data))
    }))
    DBI::dbWithTransaction(con, {
      upsert_rows(con,'datasets',datasets,'dataset_id')
      DBI::dbWriteTable(con,'_selected_games',x$games['game_id'],temporary=TRUE,overwrite=TRUE)
      for (table in names(x)) {
        rows <- deduplicate(x[[table]],table_keys[[table]])
        # Historical entities are shared across seasons; fact snapshots replace selected games.
        if (table %in% c('player_box_scores','team_box_scores','pbp_events','shot_attempts','substitutions')) {
          DBI::dbExecute(con,sprintf('DELETE FROM "%s" WHERE game_id IN (SELECT game_id FROM _selected_games)',table))
        }
        upsert_rows(con,table,rows,table_keys[[table]])
      }
      DBI::dbRemoveTable(con,'_selected_games')
      DBI::dbExecute(con,'UPDATE ingestion_runs SET finished_at=?, status=?, message=? WHERE run_id=?',params=list(Sys.time(),'success',paste(nrow(x$games),'games'),run))
    })
    invisible(list(games=nrow(x$games),report=report))
  },error=function(err) {
    DBI::dbExecute(con,'UPDATE ingestion_runs SET finished_at=?,status=?,message=? WHERE run_id=?',params=list(Sys.time(),'failed',conditionMessage(err),run))
    stop(err)
  })
}

ingest_season <- function(con,season,revision=archive_revision,refresh=FALSE,max_games=Inf,batch_size=100L) {
  # Fetch failures are durable even if no dataset could be registered.
  bundle <- tryCatch(fetch_season(season,revision,refresh),error=function(err) {
    DBI::dbExecute(con,'INSERT INTO ingestion_runs VALUES (?, ?, ?, ?, ?, ?, ?)',params=list(paste0('fetch:',sample.int(1e9,1)),'sportsdataverse',season,Sys.time(),Sys.time(),'failed',conditionMessage(err)))
    stop(err)
  })
  s <- bundle$schedules$data
  eligible <- as.character(s$game_id[eligible_schedule(s)])
  existing <- DBI::dbGetQuery(con,'SELECT game_id FROM games WHERE season=?',params=list(season))$game_id
  ids <- if (refresh) eligible else setdiff(eligible,existing)
  ids <- head(ids,max_games)
  if (!length(ids)) return(invisible('Already up to date'))
  # A bad game must be visible but must not block all other historical games.
  failed <- character()
  batches <- split(ids,ceiling(seq_along(ids)/batch_size))
  for (batch in batches) {
    tryCatch(ingest_bundle(con,bundle,season,batch),error=function(err) {
      message('Batch failed; validating individual games: ',conditionMessage(err))
      for (id in batch) tryCatch(ingest_bundle(con,bundle,season,id),error=function(e) {
        message('Quarantined ',id,': ',conditionMessage(e)); failed <<- c(failed,id)
      })
    })
  }
  if(length(failed)) stop('Incomplete season; quarantined game IDs: ',paste(failed,collapse=', '))
  invisible(length(ids))
}
