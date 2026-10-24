withr::local_dir(Sys.getenv('WYB_ROOT'))
testthat::test_that('alternative team-box recovery preserves provenance and labels dependent checks', {
  con<-connect_warehouse(':memory:');on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  b<-readRDS('data/sample/bundle.rds');id<-as.character(b$schedules$data$game_id[1]);s<-b$schedules$data[1,,drop=FALSE]
  path<-'data/sample/independent_team_totals.csv'
  import_reference(con,load_reference_fixture())
  inv<-data.frame(game_id=id,season='2024-25',game_date=as.Date(s$game_date),home_team_id=provider_id(s$home_id),away_team_id=provider_id(s$away_id),has_player_box=TRUE,has_team_box=TRUE,has_pbp=TRUE,validation_status='quarantined',dataset_id='synthetic-invalid-box')
  upsert_rows(con,'schedule_inventory',inv,'game_id')
  upsert_rows(con,'quality_exceptions',exception_rows(id,'2024-25','ingestion','player fga differs from team total','synthetic regression'),'exception_id')
  b$team_box$data$field_goals_attempted[as.character(b$team_box$data$game_id)==id]<-b$team_box$data$field_goals_attempted[as.character(b$team_box$data$game_id)==id]-1L
  fn<-recover_reference_boxes;scope<-new.env(parent=environment(fn));scope$fetch_season<-function(...)b;environment(fn)<-scope
  testthat::expect_message(recovered<-fn(con),'Recovered 1')
  testthat::expect_equal(recovered,id)
  testthat::expect_equal(nrow(DBI::dbReadTable(con,'pbp_events')),sum(as.character(b$pbp$data$game_id)==id))
  raw_manifest<-DBI::dbReadTable(con,'datasets')
  testthat::expect_equal(raw_manifest$row_count[raw_manifest$dataset_id==DBI::dbReadTable(con,'games')$dataset_id],as.numeric(nrow(b$schedules$data)))
  testthat::expect_true(all(grepl('^kaggle:',DBI::dbReadTable(con,'team_box_scores')$dataset_id)))
  testthat::expect_equal(nrow(reconcile_game_totals(con)),0L)
  checks<-DBI::dbReadTable(con,'reconciliation_checks')
  testthat::expect_equal(sum(!checks$independent),18L)
  testthat::expect_true(all(checks$independent[checks$metric=='schedule_points']))
  reconstruct_season(con,'2024-25')
  report<-completeness_report(con,years=2025,directory=tempfile())
  testthat::expect_equal(report$reference_dependent_box_games,1L)
  testthat::expect_equal(report$reference_agree_games,1L)
  testthat::expect_equal(report$fully_reconciled_games,0L)
  # A different snapshot from the same provider still is not independent.
  original<-DBI::dbReadTable(con,'datasets')
  original<-original[original$dataset_id%in%unique(DBI::dbReadTable(con,'team_box_scores')$dataset_id),,drop=FALSE]
  original$dataset_id<-'kaggle:another-snapshot-same-provider'
  upsert_rows(con,'datasets',original,'dataset_id')
  DBI::dbExecute(con,"UPDATE team_box_scores SET dataset_id='kaggle:another-snapshot-same-provider'")
  reconcile_game_totals(con)
  testthat::expect_equal(sum(!DBI::dbReadTable(con,'reconciliation_checks')$independent),18L)
})
