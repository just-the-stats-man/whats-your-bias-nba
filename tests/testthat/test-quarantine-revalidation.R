withr::local_dir(Sys.getenv('WYB_ROOT'))

testthat::test_that('current gates revalidate old quarantines without accepting source gaps', {
  con<-connect_warehouse(':memory:');on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  b<-readRDS('data/sample/bundle.rds');ingest_bundle(con,b,'2024-25')
  g<-DBI::dbGetQuery(con,'SELECT * FROM games ORDER BY game_id LIMIT 1')
  inv<-data.frame(game_id=g$game_id,season=g$season,game_date=g$game_date,home_team_id=g$home_team_id,away_team_id=g$away_team_id,has_player_box=TRUE,has_team_box=TRUE,has_pbp=TRUE,validation_status='quarantined',dataset_id=g$dataset_id)
  upsert_rows(con,'schedule_inventory',inv,'game_id');withdraw_quarantined(con)
  old<-exception_rows(g$game_id,g$season,'ingestion','prior validation defect','historical regression');old$version<-'prior-method'
  upsert_rows(con,'quality_exceptions',old,'exception_id')
  fn<-refresh_quarantine_diagnostics;scope<-new.env(parent=environment(fn))
  scope$fetch_season<-function(...)b;scope$file.exists<-function(...)TRUE;environment(fn)<-scope
  testthat::expect_length(fn(con),0L)
  testthat::expect_equal(DBI::dbGetQuery(con,'SELECT count(*) n FROM games')$n,2)
  testthat::expect_length(fn(con,recover=TRUE,seasons='2015-16'),0L)
  testthat::expect_equal(fn(con,recover=TRUE),g$game_id)
  testthat::expect_equal(DBI::dbGetQuery(con,'SELECT count(*) n FROM games')$n,3)
  testthat::expect_true(any(DBI::dbReadTable(con,'quality_exceptions')$version=='prior-method'))
  testthat::expect_equal(DBI::dbGetQuery(con,'SELECT validation_status FROM schedule_inventory')$validation_status,'passed')
  inv$validation_status<-'quarantined';upsert_rows(con,'schedule_inventory',inv,'game_id');withdraw_quarantined(con)
  b$player_box$data<-b$player_box$data[as.character(b$player_box$data$game_id)!=g$game_id,,drop=FALSE]
  testthat::expect_length(fn(con,recover=TRUE),0L)
  testthat::expect_equal(DBI::dbGetQuery(con,'SELECT count(*) n FROM games')$n,2)
})
