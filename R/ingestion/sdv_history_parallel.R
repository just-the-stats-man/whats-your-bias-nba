sdv_history_stage <- function(task) {
  stopifnot(sdv_effective_version(task$season)==task$version)
  con<-connect_warehouse(task$path);on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  DBI::dbExecute(con,'SET threads=1');DBI::dbExecute(con,"SET memory_limit='512MB'")
  if(season_end(task$season)%in%c(1999L,2000L))ingest_sdv_mixed_calendar(con,task$season) else ingest_sdv_history(con,task$season)
  list(season=task$season,path=task$path,signature=DBI::dbGetQuery(con,'SELECT signature FROM sdv_history_checkpoints')$signature)
}

ingest_sdv_history_parallel <- function(con,seasons,workers=4L) {
  sdv_history_schema(con)
  tasks<-list()
  for(season in seasons) {
    version<-sdv_effective_version(season)
    year<-season_end(season);kinds<-c(schedules='nba_schedule',player_box='player_box',team_box='team_box',pbp='play_by_play')
    if(year<2002L)kinds<-kinds[names(kinds)!='pbp']
    paths<-file.path('data/raw',archive_revision,paste0(kinds,'_',year,'.parquet'))
    if(!all(file.exists(paths)))stop('Cache the pinned archive before parallel ingestion')
    signature<-substr(digest::digest(list(stats::setNames(vapply(paths,file_sha256,character(1)),names(kinds)),version),algo='sha256'),1,24)
    if(nrow(DBI::dbGetQuery(con,'SELECT * FROM sdv_history_checkpoints WHERE season=? AND signature=?',params=list(season,signature))))next
    folder<-file.path('data/processed/sdv_stage',version,season);dir.create(folder,recursive=TRUE,showWarnings=FALSE)
    tasks[[length(tasks)+1L]]<-list(season=season,path=normalizePath(file.path(folder,'stage.duckdb'),winslash='/',mustWork=FALSE),version=version)
  }
  if(!length(tasks))return(invisible(NULL))
  cluster<-parallel::makePSOCKcluster(min(workers,length(tasks)),outfile='data/processed/phase2/sdv_stage_workers.log')
  on.exit(try(parallel::stopCluster(cluster),silent=TRUE),add=TRUE)
  parallel::clusterCall(cluster,function(path){setwd(path);source('scripts/load.R');NULL},normalizePath('.',winslash='/'))
  results<-parallel::parLapplyLB(cluster,tasks,sdv_history_stage)
  parallel::stopCluster(cluster);cluster<-NULL
  # Source checkpoints survive process interruption. Publication is per season;
  # re-entry skips already-published signatures and reuses completed staging DBs.
  for(result in results) {
    DBI::dbExecute(con,paste('ATTACH',DBI::dbQuoteString(con,result$path),'AS sdv_stage (READ_ONLY)'))
    tryCatch(DBI::dbWithTransaction(con,{
      conflict<-DBI::dbGetQuery(con,'SELECT count(*) n FROM games g JOIN sdv_stage.main.schedule_inventory s USING(game_id) WHERE g.season!=s.season OR g.season>=\'2015-16\'')$n
      if(conflict)stop('Historical source overlaps protected game IDs')
      DBI::dbExecute(con,'CREATE OR REPLACE TEMP TABLE _sdv_publish_games AS SELECT game_id FROM sdv_stage.main.schedule_inventory')
      DBI::dbExecute(con,'DELETE FROM lineup_players WHERE lineup_id IN (SELECT lineup_id FROM lineups WHERE game_id IN (SELECT game_id FROM _sdv_publish_games))')
      for(t in c('lineups','possessions','possession_events','non_possession_points','lineup_minute_checks','reconstruction_status','pbp_reconciliation_checks','reconciliation_checks','player_box_scores','team_box_scores','pbp_events','shot_attempts','substitutions','games'))DBI::dbExecute(con,paste('DELETE FROM',t,'WHERE game_id IN (SELECT game_id FROM _sdv_publish_games)'))
      DBI::dbExecute(con,'INSERT OR IGNORE INTO sources SELECT * FROM sdv_stage.main.sources')
      DBI::dbExecute(con,'INSERT OR IGNORE INTO datasets SELECT * FROM sdv_stage.main.datasets')
      DBI::dbExecute(con,'INSERT OR IGNORE INTO dataset_dependencies SELECT * FROM sdv_stage.main.dataset_dependencies')
      DBI::dbExecute(con,'INSERT OR IGNORE INTO players SELECT * FROM sdv_stage.main.players')
      DBI::dbExecute(con,'INSERT OR IGNORE INTO player_identifiers SELECT * FROM sdv_stage.main.player_identifiers')
      DBI::dbExecute(con,'INSERT OR IGNORE INTO teams SELECT * FROM sdv_stage.main.teams')
      DBI::dbExecute(con,'INSERT OR IGNORE INTO seasons SELECT * FROM sdv_stage.main.seasons')
      for(t in c('team_identities','games','player_box_scores','team_box_scores','pbp_events','shot_attempts','substitutions','reconstruction_status','schedule_inventory','sdv_history_status','sdv_history_checkpoints','quality_exceptions'))DBI::dbExecute(con,paste('INSERT OR REPLACE INTO',t,'BY NAME SELECT * FROM sdv_stage.main.',t))
      assert_warehouse_integrity(con)
    }),finally=DBI::dbExecute(con,'DETACH sdv_stage'))
    message(result$season,': staged observations published')
  }
  invisible(results)
}
