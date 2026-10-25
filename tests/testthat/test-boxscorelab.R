testthat::test_that('supplementary game counts require reciprocal opponents and scoring identity', {
  x<-data.frame(season='2022-23',game_date='2023-01-01',team=c('A','B'),opponent=c('B','A'),home=c('True','False'),result=c('W','L'),points=c('100','90'),opponent_points=c('90','100'),point_diff=c('10','-10'),field_goals_made=c('40','35'),field_goal_attempts='80',three_point_makes='10',three_point_attempts='30',free_throws_made='10',free_throw_attempts='15',rebounds='40',offensive_rebounds='10',defensive_rebounds='30')
  testthat::expect_true(all(boxscorelab_game_checks(x)))
  bad<-x;bad$points[1]<-'101';testthat::expect_false(any(boxscorelab_game_checks(bad)))
  testthat::expect_false(any(boxscorelab_game_checks(x[1,,drop=FALSE])))
  testthat::expect_false(any(boxscorelab_game_checks(rbind(x,x))))
})
