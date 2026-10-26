withr::local_dir(Sys.getenv('WYB_ROOT'))
terminal_fixture <- function() {
  con<-DBI::dbConnect(duckdb::duckdb(),dbdir=':memory:')
  # Synthetic shape reproducing the documented late-correction failure: native
  # event ID 707 is from 9:38, while explicit Game End is native ID 703.
  DBI::dbWriteTable(con,'historical_events',data.frame(snapshot_id='test',source_row=1:3,game_id='nba:g',season='2023-24',event_id=c('703','706','707'),period=4L,clock=c('PT00M00.00S','PT09M38.00S','PT09M38.00S'),event_type=c('game','2pt','rebound'),description=c('Game End','MISS shot','REBOUND'),home_score=c(106,79,79),away_score=c(114,90,90)))
  DBI::dbWriteTable(con,'historical_games',data.frame(game_id='nba:g',home_team_id='nba:h',away_team_id='nba:a',home_score=106,away_score=114))
  DBI::dbWriteTable(con,'historical_team_boxes',data.frame(game_id='nba:g',season='2023-24',team_id=c('nba:h','nba:a'),points=c(106,114),points_status='observed',validation_status='observed'))
  con
}
testthat::test_that('explicit terminal scores do not depend on numeric event IDs or physical row order', {
  con<-terminal_fixture();on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  x<-terminal_score_evidence(con,'2023-24')
  testthat::expect_true(x$eligible);testthat::expect_equal(x$event_id,'703')
  testthat::expect_equal(x$home_score,106);testthat::expect_equal(x$away_score,114)
  DBI::dbExecute(con,'UPDATE historical_events SET source_row=10-source_row')
  testthat::expect_true(terminal_score_evidence(con)$eligible)
  DBI::dbExecute(con,"UPDATE historical_events SET clock='PT00M01.00S' WHERE event_type='game'")
  testthat::expect_false(terminal_score_evidence(con)$eligible)
})
testthat::test_that('competing terminal markers and box disagreement remain unresolved', {
  con<-terminal_fixture();on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  DBI::dbExecute(con,"INSERT INTO historical_events SELECT snapshot_id,99,game_id,season,'999',period,clock,event_type,description,home_score+1,away_score FROM historical_events WHERE event_type='game'")
  testthat::expect_false(terminal_score_evidence(con)$eligible)
  DBI::dbExecute(con,'DELETE FROM historical_events WHERE source_row=99')
  DBI::dbExecute(con,"UPDATE historical_team_boxes SET points=105 WHERE team_id='nba:h'")
  testthat::expect_false(terminal_score_evidence(con)$eligible)
  DBI::dbExecute(con,"UPDATE historical_team_boxes SET points=106,points_status='source_missing' WHERE team_id='nba:h'")
  testthat::expect_false(terminal_score_evidence(con)$eligible)
  DBI::dbExecute(con,"UPDATE historical_events SET period=5 WHERE event_type='rebound'")
  testthat::expect_false(terminal_score_evidence(con)$valid_terminal)
})
