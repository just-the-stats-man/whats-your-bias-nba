withr::local_dir(Sys.getenv('WYB_ROOT'))
terminal_shot_fixture <- function() {
  con<-connect_warehouse(':memory:');shot_recovery_schema(con);template<-DBI::dbReadTable(con,'shot_recovery_candidates');DBI::dbDisconnect(con,shutdown=TRUE)
  c<-template[rep(NA_integer_,8),];rownames(c)<-NULL
  c$game_id<-'g';c$season<-'2023-24';c$event_id<-as.character(1:8);c$event_order<-1:8;c$period<-1L;c$clock<-paste0('10:0',1:8);c$player_id<-rep(c('p1','p2'),each=4);c$team_id<-rep(c('a','b'),each=4);c$made<-rep(c(TRUE,TRUE,FALSE,FALSE),2);c$points_attempted<-rep(c(2L,3L,NA,NA),2);c$source_row<-1:8;c$source_dataset_id<-'source';c$dataset_id<-'old';c$certification_status<-'noncertified';c$reason<-'game_shooting_totals_not_certified';c$classification_rule<-'source_made_value';c$value_status<-'observed';c$coordinate_status<-'source_missing';c$coordinate_system<-'source_frame_unverified'
  e<-data.frame(event_id=c$event_id,score_value=rep(c(2,3,0,0),2),event_type='Jump Shot',description='jumper')
  b<-data.frame(game_id='g',team_id=c('a','b'),fga=4,fgm=2,fg3a=2,fg3m=1)
  ref<-data.frame(game_id='g',player_id=c$player_id,team_id=c$team_id,period=1L,clock_seconds=601:608,made=c$made,points_attempted=rep(c(2L,3L,2L,3L),2),snapshot_id='nba-snapshot',source_row=101:108,nba_event_id=paste0('n',1:8),nba_game_id='nba:g',nba_player_id=rep(c('nba:p1','nba:p2'),each=4),evidence='strict original identity gates')
  terminal<-data.frame(game_id='nba:g',snapshot_id='nba-snapshot',source_row=999,event_id='end',eligible=TRUE)
  list(c=c,e=e,b=b,ref=ref,t=terminal)
}
testthat::test_that('terminal shot enrichment retains native evidence and requires all prior gates', {
  x<-terminal_shot_fixture();r<-stage_terminal_shot_game(x$c,x$e,x$b,x$ref,x$t)
  testthat::expect_true(r$passed);testthat::expect_equal(r$filled_values,4)
  testthat::expect_equal(r$candidates$points_attempted,rep(c(2L,3L,2L,3L),2))
  testthat::expect_identical(r$candidates$source_row,x$c$source_row)
  testthat::expect_true(all(is.na(r$candidates$x)))
  testthat::expect_true(all(r$candidates$value_status[c(3,4,7,8)]=='reconstructed'))
  repeat_result<-stage_terminal_shot_game(x$c,x$e,x$b,x$ref[8:1,],x$t)
  testthat::expect_identical(repeat_result$signature,r$signature)
  x$t$eligible<-FALSE;testthat::expect_false(stage_terminal_shot_game(x$c,x$e,x$b,x$ref,x$t)$passed)
  x$t$eligible<-TRUE;x$c$reason[1]<-'unverified_player_or_team_mapping'
  testthat::expect_false(stage_terminal_shot_game(x$c,x$e,x$b,x$ref,x$t)$passed)
  x$c$reason[1]<-'game_shooting_totals_not_certified';x$b$fga[1]<-5
  testthat::expect_false(stage_terminal_shot_game(x$c,x$e,x$b,x$ref,x$t)$passed)
})
