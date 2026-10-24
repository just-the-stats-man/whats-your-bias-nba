withr::local_dir(Sys.getenv('WYB_ROOT'))

testthat::test_that('missing independent team IDs require unique explicit provider metadata', {
  source_path<-'data/sample/independent_player_rows.csv';team_path<-'data/sample/independent_team_totals.csv'
  expected<-reference_player_sums(source_path,team_path)
  p<-utils::read.csv(source_path,stringsAsFactors=FALSE);p$playerteamId<-NA_real_
  path<-tempfile(fileext='.csv');on.exit(unlink(path));utils::write.csv(p,path,row.names=FALSE,na='')
  resolved<-reference_player_sums(path,team_path)
  key<-function(d)paste(d$source_game_id,d$nba_team_id)
  ix<-match(key(expected),key(resolved))
  testthat::expect_equal(resolved$player_turnovers[ix],expected$player_turnovers)
  testthat::expect_equal(sum(as.numeric(resolved$mapped_team_rows)),nrow(p))
  testthat::expect_equal(sum(as.numeric(resolved$unresolved_team_rows)),0)
  p$playerteamName[1]<-'Conflicting source team name';utils::write.csv(p,path,row.names=FALSE,na='')
  conflict<-reference_player_sums(path,team_path);id<-sprintf('%010.0f',as.numeric(p$gameId[1]))
  testthat::expect_true(all(is.na(conflict$player_turnovers[conflict$source_game_id==id])))
})

testthat::test_that('unobserved and fractional independent turnovers never become verified zeros or rounded counts', {
  p<-utils::read.csv('data/sample/independent_player_rows.csv',stringsAsFactors=FALSE)
  path<-tempfile(fileext='.csv');on.exit(unlink(path));id<-sprintf('%010.0f',as.numeric(p$gameId[1]))
  for(value in c(NA_real_,.5)) {
    p$turnovers[1]<-value;utils::write.csv(p,path,row.names=FALSE,na='')
    d<-reference_player_sums(path,'data/sample/independent_team_totals.csv')
    testthat::expect_true(any(is.na(d$player_turnovers[d$source_game_id==id])))
  }
})

testthat::test_that('numeric representations of the same player ID cannot bypass duplicate detection', {
  p<-utils::read.csv('data/sample/independent_player_rows.csv',stringsAsFactors=FALSE)
  p$personId<-as.character(p$personId);duplicate<-p[1,,drop=FALSE];duplicate$personId<-paste0(duplicate$personId,'.0')
  path<-tempfile(fileext='.csv');on.exit(unlink(path));utils::write.csv(rbind(p,duplicate),path,row.names=FALSE,na='')
  d<-reference_player_sums(path,'data/sample/independent_team_totals.csv');id<-sprintf('%010.0f',as.numeric(p$gameId[1]))
  testthat::expect_true(any(is.na(d$player_turnovers[d$source_game_id==id])))
})
