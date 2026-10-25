withr::local_dir(Sys.getenv('WYB_ROOT'))
old_sdv_fixture <- function() {
  b<-readRDS('data/sample/bundle.rds')
  b$schedules$data$season<-2004L;b$schedules$data$game_date<-as.Date('2004-03-01')
  t<-b$team_box$data;t$turnovers<-t$total_turnovers;t$team_turnovers<-t$turnovers;t$total_turnovers<-2*t$turnovers;b$team_box$data<-t
  for(k in names(b)) {
    path<-tempfile(fileext='.parquet');arrow::write_parquet(b[[k]]$data,path)
    b[[k]]$path<-path;b[[k]]$sha256<-file_sha256(path)
  }
  b
}

testthat::test_that('historical duplicated turnover components retain the recorded total and complete player sum', {
  b<-old_sdv_fixture();before<-b$team_box$data
  x<-normalize_sdv_history(b,'2003-04')
  expected<-readRDS('data/sample/bundle.rds')$team_box$data
  testthat::expect_equal(x$team_box_scores$turnovers,as.integer(expected$turnovers))
  testthat::expect_equal(x$team_box_scores$total_turnovers,as.integer(expected$total_turnovers))
  testthat::expect_identical(b$team_box$data,before)
  testthat::expect_false(any(sdv_box_quality(x)$severity=='error'))
  testthat::expect_error(normalize_sdv_history(b,'2024-25'),'cannot replace')
})

testthat::test_that('attempt constraints classify unique assignments and leave mixed assignments unknown', {
  b<-old_sdv_fixture();e<-b$pbp$data
  f<-which(e$shooting_play%in%TRUE & !e$scoring_play%in%TRUE & e$points_attempted%in%c(2,3))
  groups<-split(f,paste(e$game_id[f],e$team_id[f]))
  pair<-NULL
  for(ix in groups)if(any(e$points_attempted[ix]==2) && any(e$points_attempted[ix]==3)){pair<-c(ix[which(e$points_attempted[ix]==2)[1]],ix[which(e$points_attempted[ix]==3)[1]]);break}
  stopifnot(length(pair)==2)
  e$points_attempted[pair[1]]<-NA;e$text[pair[1]]<-'Unclassified missed jump shot';b$pbp$data<-e
  x<-normalize_sdv_history(b,'2003-04')
  testthat::expect_equal(x$pbp_events$points_attempted[pair[1]],2L)
  testthat::expect_true(any(attr(x,'normalization_notes')$rule=='unique_attempt_count_constraint'))
  e$points_attempted[pair[2]]<-NA;e$text[pair[2]]<-'Unclassified missed jump shot';b$pbp$data<-e
  y<-normalize_sdv_history(b,'2003-04')
  testthat::expect_true(all(is.na(y$pbp_events$points_attempted[pair])))
})

testthat::test_that('vectorized historical classification agrees with the established per-game parser', {
  x<-normalize_bundle(readRDS('data/sample/bundle.rds'),'2024-25')
  for(ix in split(seq_len(nrow(x$pbp_events)),x$pbp_events$game_id)) {
    e<-x$pbp_events[ix,];actual<-sdv_attempt_features(e);expected<-event_features(e,x$player_box_scores)
    for(k in names(actual))testthat::expect_equal(actual[[k]],expected[[k]])
  }
})

testthat::test_that('valid boxes survive absent PBP and ingestion resumes without rewriting checkpoints', {
  b<-old_sdv_fixture();b$pbp$data<-b$pbp$data[FALSE,]
  con<-connect_warehouse(':memory:');on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  fn<-ingest_sdv_history;scope<-new.env(parent=environment(fn));scope$fetch_sdv_history<-function(...)b;environment(fn)<-scope
  destination<-tempfile();fn(con,'2003-04',directory=destination)
  testthat::expect_equal(DBI::dbGetQuery(con,'SELECT count(*) n FROM games')$n,3)
  testthat::expect_equal(DBI::dbGetQuery(con,'SELECT count(*) n FROM pbp_events')$n,0)
  testthat::expect_true(all(DBI::dbReadTable(con,'reconstruction_status')$possessions_status=='unavailable_pbp'))
  before<-DBI::dbReadTable(con,'sdv_history_checkpoints')
  testthat::expect_equal(fn(con,'2003-04',directory=destination),'unchanged')
  testthat::expect_equal(DBI::dbReadTable(con,'sdv_history_checkpoints'),before)
  testthat::expect_silent(assert_warehouse_integrity(con))
})
