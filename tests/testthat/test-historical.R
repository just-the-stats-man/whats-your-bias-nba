withr::local_dir(Sys.getenv('WYB_ROOT'))

history_fixture <- function() {
  # Deliberately small synthetic records: one pre-three-point game and one
  # LeBron-era game. These are test evidence, not actual NBA observations.
  g<-data.frame(gameId=c('24600001','20300001'),gameDateTimeEst=c('1946-11-01','2003-11-01'),hometeamId='1',awayteamId='2',homeScore=10,awayScore=8)
  metrics<-historical_metrics()
  t<-data.frame(gameId=rep(g$gameId,each=2),teamId=rep(c('1','2'),2))
  for(column in metrics$source_column)t[[column]]<-0
  t$points<-NULL;t$teamScore<-rep(c(10,8),2)
  t$fieldGoalsMade<-rep(c(5,4),2);t$fieldGoalsAttempted<-rep(c(10,8),2)
  t$assists<-2;t$reboundsTotal<-3;t$numMinutes<-240;t$turnoversTeam<-0
  p<-t;p$personId<-rep(c('11','22'),2);p$playerteamId<-p$teamId;p$teamId<-NULL
  p$opponentteamId<-rep(c('2','1'),2);p$home<-rep(c('1','0'),2)
  p$points<-p$teamScore;p$teamScore<-NULL;p$numMinutes<-48
  d<-list(games=g,team=t,player=p)
  lapply(names(d),function(k) {
    path<-tempfile(fileext='.csv');utils::write.csv(d[[k]],path,row.names=FALSE,na='')
    list(kind=k,path=path,url='synthetic:test',revision='fixture',sha256=file_sha256(path))
  }) |> stats::setNames(names(d))
}

testthat::test_that('NBA season centuries require a consistent date and suffix', {
  testthat::expect_equal(nba_season_start(c('24600052','20300001','21900001','20000001'),c('1946-11-26','2004-04-01','2020-08-01','2000-11-01')),c(1946L,2003L,2019L,2000L))
  testthat::expect_true(is.na(nba_season_start('20300001','1946-11-26')))
  testthat::expect_true(is.na(nba_season_start('bad','2003-11-01')))
})

testthat::test_that('historical boxes preserve observations and era missingness idempotently', {
  con<-connect_warehouse(':memory:');on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  items<-history_fixture();items$team$data<-NULL
  ingest_historical_boxes(con,items)
  t<-DBI::dbGetQuery(con,'SELECT * FROM historical_team_boxes ORDER BY season,team_id')
  testthat::expect_equal(nrow(t),4L)
  testthat::expect_equal(t$fg3m_status[1:2],rep('not_applicable',2))
  testthat::expect_true(all(is.na(t$fg3m[1:2])))
  testthat::expect_equal(t$turnovers_status[1:2],rep('not_collected',2))
  testthat::expect_equal(t$validation_status,rep('observed',4))
  testthat::expect_equal(t$fg3m[3:4],c(0,0))
  before<-DBI::dbReadTable(con,'historical_checkpoints')
  ingest_historical_boxes(con,items)
  testthat::expect_equal(DBI::dbReadTable(con,'historical_checkpoints'),before)
  testthat::expect_equal(DBI::dbGetQuery(con,'SELECT count(*) n FROM games')$n,0)
  testthat::expect_equal(DBI::dbGetQuery(con,"SELECT count(*) n FROM historical_box_checks WHERE status='failed_validation'")$n,0)
})

testthat::test_that('historical placeholders and contradictory boxes do not become observations', {
  con<-connect_warehouse(':memory:');on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  items<-history_fixture();d<-utils::read.csv(items$team$path)
  d$fieldGoalsAttempted[3]<-0;d$teamScore[4]<-99
  utils::write.csv(d,items$team$path,row.names=FALSE);items$team$sha256<-file_sha256(items$team$path)
  ingest_historical_boxes(con,items)
  t<-DBI::dbGetQuery(con,"SELECT * FROM historical_team_boxes WHERE season='2003-04' ORDER BY team_id")
  testthat::expect_equal(t$fga_status[1],'source_missing')
  testthat::expect_true(is.na(t$fga[1]))
  testthat::expect_equal(t$validation_status[2],'failed_validation')
  testthat::expect_gt(DBI::dbGetQuery(con,'SELECT count(*) n FROM historical_exceptions')$n,0)
  testthat::expect_true(file.exists(items$team$path))
})

testthat::test_that('missing player team identity needs exact same-provider opposing ID', {
  con<-connect_warehouse(':memory:');on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  items<-history_fixture();d<-utils::read.csv(items$player$path)
  d$playerteamId<-NA;d$opponentteamId[4]<-'999'
  utils::write.csv(d,items$player$path,row.names=FALSE,na='');items$player$sha256<-file_sha256(items$player$path)
  ingest_historical_boxes(con,items)
  p<-DBI::dbGetQuery(con,'SELECT * FROM historical_player_boxes ORDER BY source_row')
  testthat::expect_equal(p$team_id[1:3],c('nba:1','nba:2','nba:1'))
  testthat::expect_true(is.na(p$team_id[4]))
  testthat::expect_equal(p$validation_status[4],'failed_validation')
  testthat::expect_true(all(grepl('same-provider',p$identity_evidence)))
})

testthat::test_that('historical event pointers and shot fields preserve schema distinctions', {
  con<-connect_warehouse(':memory:');on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  ingest_historical_boxes(con,history_fixture())
  d<-data.frame(gameId='20300001',actionNumber=1:3,period=1L,clock=NA_character_,shortFormattedClock='11:42',actionType=c('Made Shot','3pt','Substitution'),description='synthetic fixture',teamId='1',personId='11',scoreHome=0L,scoreAway=0L,shotResult=c(NA,'Missed',NA),shotValue=c(2L,NA,NA),x=c(NA,85,NA),y=c(NA,55,NA),xLegacy=0L,yLegacy=0L,shotDistance=c(NA,25,NA))
  path<-tempfile(fileext='.parquet');arrow::write_parquet(d,path)
  item<-list(kind='pbp',path=path,url='synthetic:test',revision='fixture',sha256=file_sha256(path))
  ingest_historical_events(con,item)
  events<-DBI::dbGetQuery(con,'SELECT * FROM historical_events ORDER BY source_row')
  s<-DBI::dbGetQuery(con,'SELECT * FROM historical_shots ORDER BY source_row')
  testthat::expect_equal(as.numeric(events$source_row),1:3)
  testthat::expect_equal(s$points_attempted,c(2L,3L))
  testthat::expect_equal(s$made,c(TRUE,FALSE))
  testthat::expect_equal(s$coordinate_status,c('source_missing','observed'))
  testthat::expect_equal(s$coordinate_system,c('nba_legacy_raw','nba_live_raw'))
  historical_event_checks(con)
  checks<-DBI::dbReadTable(con,'historical_event_checks')
  testthat::expect_true(any(checks$status=='failed_validation'))
  testthat::expect_true(all(!checks$independent))
  before<-DBI::dbReadTable(con,'historical_checkpoints')
  ingest_historical_events(con,item)
  testthat::expect_equal(DBI::dbReadTable(con,'historical_checkpoints'),before)
  testthat::expect_true(all(historical_integrity(con)$passed))
  d$description<-'changed';arrow::write_parquet(d,path);item$sha256<-file_sha256(path)
  testthat::expect_error(ingest_historical_events(con,item),'Raw path changed')
})

testthat::test_that('historical reports distinguish source coverage from complete history', {
  con<-connect_warehouse(':memory:');on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  ingest_historical_boxes(con,history_fixture())
  report<-historical_completeness(con,tempfile(),tempfile())
  testthat::expect_equal(report$source_games,c(1,1))
  testthat::expect_true(all(is.na(report$expected_games)))
  testthat::expect_equal(report$canonical_games,c(0,0))
  testthat::expect_true(all(report$tracking_observations==0))
  totals<-DBI::dbGetQuery(con,'SELECT * FROM historical_team_season_totals')
  testthat::expect_true(all(totals$observation_type=='reconstructed'))
  testthat::expect_true(all(grepl('partial',totals$coverage_definition)))
  testthat::expect_error(import_historical_reference(con,'2015-16'),'cannot replace')
})

testthat::test_that('old reference benchmarks use player sums and explicit team-only turnovers', {
  con<-connect_warehouse(':memory:');on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  items<-history_fixture()
  for(kind in names(items)) {
    d<-utils::read.csv(items[[kind]]$path)
    for(column in intersect(c('hometeamId','awayteamId','teamId','playerteamId','opponentteamId'),names(d)))d[[column]]<-ifelse(d[[column]]==1,'1610612737','1610612738')
    if(kind=='team') {d$turnovers[3]<-4;d$turnoversTeam[3]<-2}
    if(kind=='player') {
      d$turnovers[3]<-1
      extras<-do.call(rbind,lapply(seq_len(nrow(d)),function(i) {
        z<-d[rep(i,4),];z$personId<-100*i+1:4
        for(column in intersect(historical_metrics()$source_column,names(z)))z[[column]]<-0
        z
      }))
      d<-rbind(d,extras)
    }
    utils::write.csv(d,items[[kind]]$path,row.names=FALSE,na='');items[[kind]]$sha256<-file_sha256(items[[kind]]$path)
  }
  ingest_historical_boxes(con,items)
  reference_dir<-tempfile()
  import_historical_reference(con,'2003-04',directory=reference_dir)
  d<-DBI::dbGetQuery(con,'SELECT * FROM independent_team_totals ORDER BY team_id')
  testthat::expect_equal(d$turnovers,c(1L,0L))
  testthat::expect_equal(d$reported_turnovers,c(4L,0L))
  testthat::expect_equal(d$total_turnovers,c(3L,0L))
  testthat::expect_equal(d$reference_player_rows,c(5L,5L))
  testthat::expect_true(all(grepl('nba-history-reference:',d$dataset_id)))
  testthat::expect_equal(DBI::dbGetQuery(con,'SELECT count(*) n FROM dataset_dependencies')$n,2)
  testthat::expect_length(list.files(reference_dir,pattern='[.]parquet$'),1L)
})

testthat::test_that('NBA identity labels remain separate from ESPN player mappings', {
  con<-connect_warehouse(':memory:');on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  frames<-list(players=data.frame(personId=c(11,22),firstName=c('Fixture','Second'),lastName='Player'),teams=data.frame(teamId=1,teamCity='Fixture',teamName='Team',teamAbbrev='FIX',seasonFounded='1946',seasonActiveTill='2026',league='NBA'))
  items<-lapply(names(frames),function(kind) {
    path<-tempfile(fileext='.csv');utils::write.csv(frames[[kind]],path,row.names=FALSE)
    list(kind=kind,path=path,url='synthetic:test',revision='fixture',sha256=file_sha256(path))
  }) |> stats::setNames(names(frames))
  fn<-ingest_historical_identities;scope<-new.env(parent=environment(fn))
  scope$historical_file<-function(kind)items[[kind]];environment(fn)<-scope
  fn(con)
  p<-DBI::dbGetQuery(con,'SELECT * FROM historical_players ORDER BY player_id')
  testthat::expect_equal(p$player_id,c('nba:11','nba:22'))
  testthat::expect_equal(p$name,c('Fixture Player','Second Player'))
  testthat::expect_equal(DBI::dbGetQuery(con,'SELECT count(*) n FROM player_identifiers')$n,0)
  testthat::expect_true(grepl('not a validated',DBI::dbReadTable(con,'historical_team_history')$evidence))
})
