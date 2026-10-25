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
  reconstruct_parallel(con,workers=1L,directory=folder,game_ids=ids[1],resume=TRUE)
  testthat::expect_equal(DBI::dbReadTable(con,'reconstruction_status'),before)
  testthat::expect_error(reconstruct_parallel(con,workers=1L,directory=folder,game_ids=ids[2],resume=TRUE),'inputs changed')
})
