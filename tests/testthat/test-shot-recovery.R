withr::local_dir(Sys.getenv('WYB_ROOT'))
shot_recovery_fixture <- function() {
  e<-data.frame(game_id='g',event_id=as.character(1:8),shooting_play=TRUE,scoring_play=rep(c(TRUE,TRUE,FALSE,FALSE),2),score_value=rep(c(2L,3L,0L,0L),2),points_attempted=NA_integer_,event_type='Jump Shot',description=rep(c('made jumper','made three point jumper','missed jumper','missed jumper'),2),team_id=rep(c('a','b'),each=4),player_id=rep(c('p1','p2'),each=4),period=1L,clock=paste0('10:0',1:8),stringsAsFactors=FALSE)
  b<-data.frame(game_id='g',team_id=c('a','b'),fga=4L,fgm=2L,fg3a=2L,fg3m=1L)
  r<-data.frame(game_id=e$game_id,team_id=e$team_id,player_id=e$player_id,period=e$period,clock_seconds=601:608,made=e$scoring_play,points_attempted=rep(c(2L,3L,2L,3L),2))
  list(e=e,b=b,r=r)
}

testthat::test_that('missing attempt annotations do not discard observed FG candidates or create shot types', {
  x<-shot_recovery_fixture();f<-shot_recovery_classify(x$e,x$b)
  testthat::expect_true(all(f$fg))
  testthat::expect_equal(sum(is.na(f$value)),4)
  q<-shot_recovery_checks(x$e,f,x$b)
  testthat::expect_true(all(q$status[q$metric%in%c('fga','fgm','fg3m')]=='match'))
  testthat::expect_true(all(q$status[q$metric=='fg3a']=='source_missing'))
  x$e$points_attempted<-rep(c(2L,3L,2L,3L),2)
  testthat::expect_true(all(shot_recovery_checks(x$e,shot_recovery_classify(x$e,x$b),x$b)$status=='match'))
})

testthat::test_that('only an identified, numerically verified coordinate frame supplies standard locations', {
  c<-shot_coordinate_evidence(c(40.75,-15.75,214748406.75,NA,1),c(0,10,214748365,NA,1),c(25,35,2147483647,NA,NA),c(1,26,2147483647,NA,NA),c(TRUE,FALSE,TRUE,TRUE,TRUE))
  testthat::expect_equal(c$coordinate_frame_validated,c(TRUE,TRUE,FALSE,FALSE,FALSE))
  testthat::expect_equal(c$x[1:2],c(40.75,-15.75))
  testthat::expect_true(all(is.na(c$x[3:5])))
  testthat::expect_equal(c$coordinate_status[3:5],c('failed_validation','source_missing','source_missing'))
  testthat::expect_equal(c$raw_transformed_x[3],214748406.75)
})

testthat::test_that('one-to-one NBA observations classify values while ambiguous source joins stay unavailable', {
  x<-shot_recovery_fixture();f<-shot_recovery_classify(x$e,x$b,x$r)
  testthat::expect_equal(f$value,x$r$points_attempted)
  testthat::expect_equal(sum(f$classification_rule=='unique_NBA_event_observation'),4)
  testthat::expect_true(all(shot_recovery_checks(x$e,f,x$b)$status=='match'))
  duplicated<-rbind(x$r,x$r[x$r$made==FALSE,])
  f<-shot_recovery_classify(x$e,x$b,duplicated)
  testthat::expect_equal(sum(is.na(f$value)),4)
  testthat::expect_true(all(is.na(f$reference_row[!x$e$scoring_play])))
  wrong<-x$r;wrong$points_attempted[1]<-3L
  f<-shot_recovery_classify(x$e,x$b,wrong)
  testthat::expect_true(f$conflict[1])
  testthat::expect_equal(f$value[1],2L)
  wrong<-x$r;wrong$made[3]<-TRUE
  f<-shot_recovery_classify(x$e,x$b,wrong)
  testthat::expect_true(f$conflict[3])
  testthat::expect_true(f$reference_outcome_checked[3])
})

testthat::test_that('FT trip annotations never become FGs and unique constraints never assign a mixed split', {
  x<-shot_recovery_fixture()
  ft<-x$e[1,,drop=FALSE];ft$event_id<-'ft';ft$event_type<-'Free Throw 2 of 2';ft$points_attempted<-2L;ft$score_value<-1L
  e<-rbind(x$e,ft);f<-shot_recovery_classify(e,x$b)
  testthat::expect_true(f$free_throw[9]);testthat::expect_false(f$fg[9])
  testthat::expect_equal(sum(f$fg),8)
  x$b$fg3a<-1L;f<-shot_recovery_classify(x$e,x$b)
  testthat::expect_equal(f$value[!x$e$scoring_play],rep(2L,4))
  testthat::expect_true(all(f$classification_rule[!x$e$scoring_play]=='unique_box_attempt_constraints'))
  x$b$fga<-5L;f<-shot_recovery_classify(x$e,x$b)
  testthat::expect_true(all(is.na(f$value[!x$e$scoring_play])))
  x$e$description[3]<-'missed 27-foot jumper'
  testthat::expect_true(is.na(shot_recovery_classify(x$e,x$b)$value[3]))
})
