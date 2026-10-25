withr::local_dir(Sys.getenv('WYB_ROOT'))
testthat::test_that('current reports exclude superseded physical errors while retaining their audit history', {
  con<-connect_warehouse(':memory:');on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  historical_schema(con);sdv_history_schema(con)
  ingest_bundle(con,readRDS('data/sample/bundle.rds'),'2024-25')
  g<-DBI::dbReadTable(con,'games');id<-g$game_id[1]
  inventory<-g[c('game_id','season','game_date','home_team_id','away_team_id','dataset_id','competition')]
  inventory$has_pbp<-inventory$has_player_box<-inventory$has_team_box<-TRUE;inventory$validation_status<-'passed'
  upsert_rows(con,'schedule_inventory',inventory,'game_id')
  input<-DBI::dbGetQuery(con,'SELECT DISTINCT dataset_id FROM pbp_events WHERE game_id=?',params=list(id))$dataset_id
  upsert_rows(con,'reconstruction_status',data.frame(game_id=id,season='2024-25',version=reconstruction_version,possessions_status='unresolved',lineups_status='unresolved',resolved_team_periods=0L,expected_team_periods=8L,updated_at=Sys.time(),dataset_id=input,reference_signature='unavailable'),'game_id')
  errors<-rbind(exception_rows(id,'2024-25','possessions','CURRENT_FAILURE','current input',dataset_id=input),exception_rows(id,'2024-25','possessions','OLD_FAILURE','older input retained',dataset_id='superseded-input'))
  upsert_rows(con,'quality_exceptions',errors,'exception_id')
  folder<-tempfile();dir.create(folder)
  execution_reports(con,directory=folder)
  report<-utils::read.csv(file.path(folder,'execution_unresolved_games.csv'))
  active<-report$active_physical_errors[report$game_id==id]
  testthat::expect_match(active,'CURRENT_FAILURE')
  testthat::expect_false(grepl('OLD_FAILURE',active))
  completeness_report(con,years=2025L,directory=folder)
  summary<-utils::read.csv(file.path(folder,'exception_summary.csv'))
  testthat::expect_equal(summary$state[summary$category=='CURRENT_FAILURE'],'active')
  testthat::expect_equal(summary$state[summary$category=='OLD_FAILURE'],'historical')
})
