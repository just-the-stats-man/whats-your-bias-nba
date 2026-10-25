# Parallel data processing, with one isolated DuckDB per season. Workers never
# write the main warehouse. The parent keeps its write lock and publishes all
# selected seasons in one transaction only after every worker passes integrity.
reconstruction_partition <- function(task) {
  stopifnot(identical(reconstruction_version,task$version))
  path<-file.path(task$directory,'results.duckdb')
  fresh<-!file.exists(path)
  con<-connect_warehouse(path)
  on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  DBI::dbExecute(con,"SET memory_limit='512MB'");DBI::dbExecute(con,'SET threads=1')
  signature<-digest::digest(vapply(task$inputs,file_sha256,character(1)),algo='sha256')
  if(fresh)DBI::dbWithTransaction(con,{
    for(table in names(task$inputs))DBI::dbExecute(con,sprintf('INSERT INTO %s BY NAME SELECT * FROM read_parquet(%s)',DBI::dbQuoteIdentifier(con,table),DBI::dbQuoteString(con,task$inputs[[table]])))
    DBI::dbExecute(con,'CREATE TABLE worker_inputs (signature VARCHAR,version VARCHAR)')
    DBI::dbExecute(con,'INSERT INTO worker_inputs VALUES (?,?)',params=list(signature,task$version))
  }) else {
    if(!DBI::dbExistsTable(con,'worker_inputs'))stop('Existing worker has no verified input checkpoint')
    saved<-DBI::dbReadTable(con,'worker_inputs')
    if(nrow(saved)!=1L || saved$signature!=signature || saved$version!=task$version)stop('Worker snapshot changed; choose a new directory')
  }
  reconstruct_season(con,task$season,batch_size=task$batch_size)
  assert_warehouse_integrity(con)
  count<-DBI::dbGetQuery(con,'SELECT count(*) n FROM reconstruction_status')$n
  stopifnot(count==DBI::dbGetQuery(con,'SELECT count(*) n FROM games')$n)
  list(season=task$season,path=path,version=reconstruction_version,games=as.numeric(count))
}

reconstruct_parallel <- function(con,seasons=NULL,workers=2L,batch_size=100L,directory=NULL,game_ids=NULL,resume=FALSE) {
  available<-DBI::dbGetQuery(con,'SELECT DISTINCT season FROM games ORDER BY season')$season
  if(is.null(seasons))seasons<-available
  if(!length(seasons))return(invisible(list()))
  if(anyDuplicated(seasons) || any(!seasons%in%available))stop('Select existing, unique warehouse seasons')
  candidates<-DBI::dbGetQuery(con,paste0('SELECT game_id,season,dataset_id FROM games WHERE season IN (',paste(DBI::dbQuoteString(con,seasons),collapse=','),') ORDER BY game_id'))
  if(!is.null(game_ids)) {
    if(anyDuplicated(game_ids) || any(!game_ids%in%candidates$game_id))stop('Select existing unique games in the requested seasons')
    candidates<-candidates[candidates$game_id%in%game_ids,,drop=FALSE]
  }
  if(!nrow(candidates))return(invisible(list()))
  seasons<-sort(unique(candidates$season))
  DBI::dbWriteTable(con,'_parallel_selection',candidates['game_id'],temporary=TRUE,overwrite=TRUE)
  signature<-digest::digest(list(version=reconstruction_version,games=candidates,events=DBI::dbGetQuery(con,'SELECT game_id,dataset_id,count(*) n FROM pbp_events WHERE game_id IN (SELECT game_id FROM _parallel_selection) GROUP BY game_id,dataset_id ORDER BY game_id,dataset_id'),checks=DBI::dbGetQuery(con,'SELECT * FROM reconciliation_checks WHERE game_id IN (SELECT game_id FROM _parallel_selection) ORDER BY game_id,team_id,reference_dataset_id,metric')),algo='sha256')
  workers<-as.integer(workers)
  if(is.na(workers) || workers<1L)stop('workers must be a positive integer')
  root<-normalizePath('.',winslash='/')
  if(is.null(directory)) {
    dir.create('data/processed',recursive=TRUE,showWarnings=FALSE)
    directory<-tempfile('reconstruction-',tmpdir=normalizePath('data/processed',winslash='/'))
  }
  saved_path<-file.path(directory,'snapshot.rds')
  reuse<-dir.exists(directory) && length(list.files(directory))>0L
  if(reuse && (!resume || !file.exists(saved_path)))stop('Use a new reconstruction output directory')
  dir.create(directory,recursive=TRUE,showWarnings=FALSE)
  directory<-normalizePath(directory,winslash='/')
  message('Reconstruction snapshot: ',directory)
  shared<-c('sources','datasets','dataset_dependencies','players','teams','independent_team_totals')
  shared_paths<-setNames(file.path(directory,paste0(shared,'.parquet')),shared)
  copy<-function(table,path,where='')DBI::dbExecute(con,sprintf('COPY (SELECT * FROM %s %s) TO %s (FORMAT PARQUET)',DBI::dbQuoteIdentifier(con,table),where,DBI::dbQuoteString(con,path)))
  if(reuse) {
    saved<-readRDS(saved_path)
    if(saved$signature!=signature)stop('Selected reconstruction inputs changed; choose a new directory')
    if(file.exists(file.path(directory,'published.rds'))) {
      stopifnot(DBI::dbGetQuery(con,'SELECT count(*) n FROM reconstruction_status WHERE game_id IN (SELECT game_id FROM _parallel_selection)')$n==nrow(candidates))
      assert_warehouse_integrity(con);return(invisible(readRDS(file.path(directory,'published.rds'))))
    }
    tasks<-saved$tasks
  } else {
    for(table in shared)copy(table,shared_paths[[table]])
    tasks<-lapply(seasons,function(season) {
    folder<-file.path(directory,season);dir.create(folder)
    local<-c('games','player_box_scores','team_box_scores','pbp_events','reconciliation_checks')
    paths<-setNames(file.path(folder,paste0(local,'.parquet')),local)
    condition<-paste0('WHERE game_id IN (SELECT game_id FROM games WHERE season=',DBI::dbQuoteString(con,season),' AND game_id IN (SELECT game_id FROM _parallel_selection))')
    for(table in local)copy(table,paths[[table]],condition)
    list(season=season,directory=folder,inputs=c(shared_paths,paths),version=reconstruction_version,batch_size=as.integer(batch_size))
    })
    saveRDS(list(signature=signature,tasks=tasks),saved_path)
  }
  if(workers==1L)results<-lapply(tasks,reconstruction_partition) else {
    log<-file.path(directory,'workers.log');message('Worker log: ',log)
    cluster<-parallel::makePSOCKcluster(min(workers,length(tasks)),outfile=log)
    on.exit(try(parallel::stopCluster(cluster),silent=TRUE),add=TRUE)
    parallel::clusterCall(cluster,function(path){setwd(path);source('scripts/load.R');NULL},root)
    results<-parallel::parLapplyLB(cluster,tasks,function(task)reconstruction_partition(task))
    parallel::stopCluster(cluster);cluster<-NULL
  }
  stopifnot(all(vapply(results,function(x)identical(x$version,reconstruction_version),logical(1))))
  keys<-list(possessions='possession_id',possession_events=c('game_id','event_id'),non_possession_points=c('game_id','event_id'),lineups='lineup_id',lineup_players=c('lineup_id','player_id'),lineup_minute_checks=c('game_id','player_id'),reconstruction_status='game_id',pbp_reconciliation_checks=c('game_id','team_id','metric'),quality_exceptions='exception_id')
  aliases<-paste0('history_worker_',seq_along(results))
  for(i in seq_along(results))DBI::dbExecute(con,paste('ATTACH',DBI::dbQuoteString(con,results[[i]]$path),'AS',aliases[i],'(READ_ONLY)'))
  on.exit(for(alias in aliases)try(DBI::dbExecute(con,paste('DETACH',alias)),silent=TRUE),add=TRUE)
  DBI::dbWithTransaction(con,{
    selected<-candidates['game_id']
    DBI::dbWriteTable(con,'_parallel_games',selected,temporary=TRUE,overwrite=TRUE)
    DBI::dbExecute(con,'DELETE FROM lineup_players WHERE lineup_id IN (SELECT lineup_id FROM lineups WHERE game_id IN (SELECT game_id FROM _parallel_games))')
    for(table in setdiff(names(keys),c('lineup_players','quality_exceptions')))DBI::dbExecute(con,paste('DELETE FROM',table,'WHERE game_id IN (SELECT game_id FROM _parallel_games)'))
    for(i in seq_along(results)) {
      result<-results[[i]]
      for(table in names(keys))DBI::dbExecute(con,paste0(if(table=='quality_exceptions')'INSERT OR REPLACE INTO ' else 'INSERT INTO ',DBI::dbQuoteIdentifier(con,table),' BY NAME SELECT * FROM ',aliases[i],'.main.',DBI::dbQuoteIdentifier(con,table)))
      message('Published season ',result$season,': ',result$games,' evaluated games')
    }
    DBI::dbRemoveTable(con,'_parallel_games')
    assert_warehouse_integrity(con)
  })
  saveRDS(results,file.path(directory,'published.rds'))
  invisible(results)
}
