withr::local_dir(Sys.getenv('WYB_ROOT'))

testthat::test_that('isolated season workers reproduce serial real-game reconstruction', {
  con<-connect_warehouse(':memory:');on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  ingest_bundle(con,readRDS('data/sample/bundle.rds'),'2024-25')
  ingest_bundle(con,readRDS('data/sample/historical_2016.rds'),'2015-16')
  import_reference(con,load_reference_fixture());reconcile_game_totals(con)
  for(season in c('2015-16','2024-25'))reconstruct_season(con,season)
  keys<-list(possessions='possession_id',possession_events=c('game_id','event_id'),non_possession_points=c('game_id','event_id'),lineups='lineup_id',lineup_players=c('lineup_id','player_id'),lineup_minute_checks=c('game_id','player_id'),pbp_reconciliation_checks=c('game_id','team_id','metric'),reconstruction_status='game_id')
  read<-function(table) {
    d<-DBI::dbReadTable(con,table);d$updated_at<-NULL
    if(nrow(d))d<-d[do.call(order,d[keys[[table]]]),,drop=FALSE]
    rownames(d)<-NULL;d
  }
  serial<-setNames(lapply(names(keys),read),names(keys))
  reconstruct_parallel(con,workers=2L,batch_size=2L,directory=tempfile('parallel-fixture-'))
  for(table in names(keys))testthat::expect_equal(read(table),serial[[table]])
  testthat::expect_silent(assert_warehouse_integrity(con))
})

testthat::test_that('scoped worker publication preserves unrelated statuses and reuses unchanged snapshots', {
  con<-connect_warehouse(':memory:');on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  ingest_bundle(con,readRDS('data/sample/bundle.rds'),'2024-25')
  import_reference(con,load_reference_fixture());reconcile_game_totals(con);reconstruct_season(con,'2024-25')
  ids<-DBI::dbGetQuery(con,'SELECT game_id FROM games ORDER BY game_id')$game_id
  protected<-DBI::dbGetQuery(con,'SELECT * FROM reconstruction_status WHERE game_id!=?',params=list(ids[1]))
  folder<-tempfile('scoped-workers-')
  reconstruct_parallel(con,workers=1L,directory=folder,game_ids=ids[1],resume=TRUE)
  testthat::expect_equal(DBI::dbGetQuery(con,'SELECT * FROM reconstruction_status WHERE game_id!=?',params=list(ids[1])),protected)
  before<-DBI::dbReadTable(con,'reconstruction_status')
  checkpoint<-readRDS(file.path(folder,'snapshot.rds'));checkpoint$signature_version<-NULL;checkpoint$signature<-'legacy-signature'
  saveRDS(checkpoint,file.path(folder,'snapshot.rds'))
  reconstruct_parallel(con,workers=1L,directory=folder,game_ids=ids[1],resume=TRUE)
  testthat::expect_equal(DBI::dbReadTable(con,'reconstruction_status'),before)
  testthat::expect_equal(readRDS(file.path(folder,'snapshot.rds'))$signature_version,2L)
  wrong_method<-checkpoint;wrong_method$tasks[[1]]$version<-'different-method'
  testthat::expect_true(is.na(frozen_reconstruction_signature(wrong_method,ids[1])))
  testthat::expect_error(reconstruct_parallel(con,workers=1L,directory=folder,game_ids=ids[2],resume=TRUE),'inputs changed')
  DBI::dbExecute(con,'UPDATE player_box_scores SET minutes=minutes+0.1 WHERE game_id=?',params=list(ids[1]))
  testthat::expect_error(reconstruct_parallel(con,workers=1L,directory=folder,game_ids=ids[1],resume=TRUE),'inputs changed')
})

testthat::test_that('snapshot signatures cover box minutes, turnover benchmarks and selected scope', {
  con<-connect_warehouse(':memory:');on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  ingest_bundle(con,readRDS('data/sample/bundle.rds'),'2024-25')
  import_reference(con,load_reference_fixture());reconcile_game_totals(con)
  ids<-DBI::dbGetQuery(con,'SELECT game_id FROM games ORDER BY game_id')$game_id
  before<-reconstruction_inputs_signature(con,ids[1])
  DBI::dbExecute(con,'UPDATE player_box_scores SET minutes=minutes+0.1 WHERE game_id=?',params=list(ids[1]))
  after_box<-reconstruction_inputs_signature(con,ids[1]);testthat::expect_false(before==after_box)
  DBI::dbExecute(con,'UPDATE independent_team_totals SET total_turnovers=coalesce(total_turnovers,0)+1 WHERE dataset_id IN (SELECT reference_dataset_id FROM reconciliation_checks WHERE game_id=?) AND source_game_id IN (SELECT reference_game_id FROM reconciliation_checks WHERE game_id=?)',params=list(ids[1],ids[1]))
  after_reference<-reconstruction_inputs_signature(con,ids[1]);testthat::expect_false(after_box==after_reference)
  DBI::dbExecute(con,'UPDATE player_box_scores SET minutes=minutes+0.1 WHERE game_id=?',params=list(ids[2]))
  testthat::expect_equal(reconstruction_inputs_signature(con,ids[1]),after_reference)
})
