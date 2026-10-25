withr::local_dir(Sys.getenv('WYB_ROOT'))
testthat::test_that('whole-box recovery identities require exact unique metadata and agreeing known counts', {
  p<-data.frame(player_id=c('nba:1','nba:2'),team_id='espn:1',minutes=c(10.5,20.5))
  for(k in c('points','fgm','fga','fg3m','fg3a','ftm','fta','assists','turnovers','rebounds'))p[[k]]<-c(0,1)
  n<-data.frame(player_id=p$player_id,name=c('First Player','Second Player'))
  e<-p;e$player_id<-c('espn:10','espn:20');e$name<-n$name;e$did_not_play<-FALSE
  testthat::expect_equal(nba_recovery_player_map(p,e,n)$player_id,e$player_id)
  bad<-e;bad$name[1]<-'Different Player';testthat::expect_null(nba_recovery_player_map(p,bad,n))
  bad<-e;bad$points[1]<-99;testthat::expect_null(nba_recovery_player_map(p,bad,n))
  bad<-e;bad$minutes[1]<-1;testthat::expect_null(nba_recovery_player_map(p,bad,n))
  bad<-e;bad$did_not_play[1]<-TRUE;testthat::expect_null(nba_recovery_player_map(p,bad,n))
  bad<-rbind(e,e[1,]);testthat::expect_null(nba_recovery_player_map(p,bad,n))
  e$points[1]<-NA;testthat::expect_equal(nba_recovery_player_map(p,e,n)$player_id,c('espn:10','espn:20'))
  extra<-e[1,,drop=FALSE];extra$player_id<-'espn:30';extra$name<-'Unmatched Participant';extra$minutes<-1
  testthat::expect_null(nba_recovery_player_map(p,rbind(e,extra),n))
})
