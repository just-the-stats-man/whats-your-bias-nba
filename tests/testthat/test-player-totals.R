withr::local_dir(Sys.getenv('WYB_ROOT'))

testthat::test_that('a correct score cannot hide a conflicting player aggregate', {
  b<-readRDS('data/sample/bundle.rds');active<-which(b$player_box$data$minutes>0)[1]
  b$player_box$data$field_goals_attempted[active]<-b$player_box$data$field_goals_attempted[active]+1L
  q<-quality_report(normalize_bundle(b,'2024-25'))
  testthat::expect_true('player fga differs from team total'%in%q$check)
  b<-readRDS('data/sample/bundle.rds');b$player_box$data$assists[active]<-NA_integer_
  q<-quality_report(normalize_bundle(b,'2024-25'))
  testthat::expect_true('player assists unavailable for team reconciliation'%in%q$check)
})

testthat::test_that('legacy inconsistent games are withdrawn without deleting provenance', {
  con<-connect_warehouse(':memory:');on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  ingest_bundle(con,readRDS('data/sample/bundle.rds'),'2024-25')
  import_reference(con,load_reference_fixture());reconcile_game_totals(con);reconstruct_season(con,'2024-25')
  manifest<-DBI::dbReadTable(con,'datasets')
  p<-DBI::dbGetQuery(con,'SELECT game_id,player_id FROM player_box_scores WHERE minutes>0 LIMIT 1')
  DBI::dbExecute(con,'UPDATE player_box_scores SET fga=fga+1 WHERE game_id=? AND player_id=?',params=list(p$game_id,p$player_id))
  findings<-suppressMessages(quarantine_inconsistent_player_totals(con))
  testthat::expect_equal(unique(findings$game_id),p$game_id)
  testthat::expect_equal(nrow(DBI::dbReadTable(con,'games')),2L)
  testthat::expect_false(p$game_id%in%DBI::dbReadTable(con,'possessions')$game_id)
  testthat::expect_false(p$game_id%in%DBI::dbReadTable(con,'pbp_reconciliation_checks')$game_id)
  testthat::expect_equal(DBI::dbReadTable(con,'datasets'),manifest)
  testthat::expect_silent(assert_warehouse_integrity(con))
})
