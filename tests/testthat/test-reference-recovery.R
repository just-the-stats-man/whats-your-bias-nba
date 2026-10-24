withr::local_dir(Sys.getenv('WYB_ROOT'))
testthat::test_that('alternative team-box recovery preserves provenance and labels dependent checks', {
  con<-connect_warehouse(':memory:');on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  b<-readRDS('data/sample/bundle.rds');id<-as.character(b$schedules$data$game_id[1]);s<-b$schedules$data[1,,drop=FALSE]
  path<-'data/sample/independent_team_totals.csv'
  import_reference(con,list(data=read.csv(path),path=path,url=reference_url,revision='kaggle-v524-filtered-fixture',sha256=file_sha256(path)))
  inv<-data.frame(game_id=id,season='2024-25',game_date=as.Date(s$game_date),home_team_id=provider_id(s$home_id),away_team_id=provider_id(s$away_id),has_player_box=TRUE,has_team_box=TRUE,has_pbp=TRUE,validation_status='quarantined',dataset_id='synthetic-invalid-box')
  upsert_rows(con,'schedule_inventory',inv,'game_id')
  upsert_rows(con,'quality_exceptions',exception_rows(id,'2024-25','ingestion','team_box_scores inconsistent scoring totals','synthetic regression'),'exception_id')
  b$team_box$data$field_goals_made[as.character(b$team_box$data$game_id)==id]<-0L
  fn<-recover_reference_boxes;scope<-new.env(parent=environment(fn));scope$fetch_season<-function(...)b;environment(fn)<-scope
  testthat::expect_message(recovered<-fn(con),'Recovered 1')
  testthat::expect_equal(recovered,id)
  testthat::expect_true(all(grepl('^kaggle:',DBI::dbReadTable(con,'team_box_scores')$dataset_id)))
  testthat::expect_equal(nrow(reconcile_game_totals(con)),0L)
  checks<-DBI::dbReadTable(con,'reconciliation_checks')
  testthat::expect_equal(sum(!checks$independent),18L)
  testthat::expect_true(all(checks$independent[checks$metric=='schedule_points']))
})
