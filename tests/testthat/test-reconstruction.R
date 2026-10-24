withr::local_dir(Sys.getenv('WYB_ROOT'))
sample_bundle <- function() readRDS('data/sample/bundle.rds')
reference_fixture <- function() {
  load_reference_fixture()
}

testthat::test_that('independent NBA-derived totals match the real ESPN sample', {
  con<-connect_warehouse(':memory:');on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  ingest_bundle(con,sample_bundle(),'2024-25');import_reference(con,reference_fixture())
  testthat::expect_equal(nrow(reconcile_game_totals(con)),0L)
  checks<-DBI::dbReadTable(con,'reconciliation_checks')
  testthat::expect_equal(nrow(checks),60L)
  testthat::expect_true(all(checks$passed))
  # Matching must never rely on equal scores: a changed reference score stays
  # matched and produces a discrepancy instead of disappearing from coverage.
  DBI::dbExecute(con,"UPDATE independent_team_totals SET points=points+1 WHERE team_id='espn:13'")
  testthat::expect_gt(nrow(reconcile_game_totals(con)),0L)
  testthat::expect_equal(nrow(DBI::dbReadTable(con,'reconciliation_checks')),60L)
  reconstruct_season(con,'2024-25')
  testthat::expect_true(all(DBI::dbReadTable(con,'reconstruction_status')$possessions_status=='unresolved'))
  testthat::expect_equal(nrow(DBI::dbReadTable(con,'possessions')),0L)
})

testthat::test_that('real possessions and complete five-player stints reconcile and repeat', {
  con<-connect_warehouse(':memory:');on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  ingest_bundle(con,sample_bundle(),'2024-25');import_reference(con,reference_fixture());reconcile_game_totals(con)
  reconstruct_season(con,'2024-25')
  status<-DBI::dbReadTable(con,'reconstruction_status')
  testthat::expect_true(all(status$possessions_status=='reconciled'))
  testthat::expect_true(all(status$lineups_status=='reconciled'))
  testthat::expect_true(all(status$resolved_team_periods==status$expected_team_periods))
  testthat::expect_true(all(DBI::dbReadTable(con,'lineup_minute_checks')$passed))
  testthat::expect_equal(nrow(DBI::dbGetQuery(con,'SELECT lineup_id FROM lineup_players GROUP BY lineup_id HAVING count(*)!=5 OR count(DISTINCT player_id)!=5')),0L)
  time<-DBI::dbGetQuery(con,'SELECT game_id,team_id,sum(duration_seconds) AS total_seconds FROM lineups GROUP BY game_id,team_id')
  testthat::expect_true(all(time$total_seconds==2880))
  score<-DBI::dbGetQuery(con,'SELECT game_id,team_id,sum(points) points FROM (SELECT game_id,offense_team_id team_id,points FROM possessions UNION ALL SELECT game_id,team_id,points FROM non_possession_points) GROUP BY game_id,team_id')
  expected<-DBI::dbReadTable(con,'team_box_scores');j<-match(paste(score$game_id,score$team_id),paste(expected$game_id,expected$team_id))
  testthat::expect_equal(score$points,as.numeric(expected$points[j]))
  testthat::expect_gt(nrow(get_game_possessions(status$game_id[1],con)),150L)
  lineups<-get_team_lineups('LAL','2024-25',con)
  testthat::expect_true(all(lengths(lineups$player_ids)==5L))
  before<-DBI::dbGetQuery(con,'SELECT count(*) n FROM possessions')$n
  reconstruct_season(con,'2024-25',force=TRUE)
  testthat::expect_equal(DBI::dbGetQuery(con,'SELECT count(*) n FROM possessions')$n,before)
  testthat::expect_equal(nrow(DBI::dbReadTable(con,'matchup_observations')),0L)
  testthat::expect_silent(assert_warehouse_integrity(con))
  DBI::dbExecute(con,"UPDATE independent_team_totals SET fgm=fgm+1 WHERE team_id='espn:13'")
  reconcile_game_totals(con)
  testthat::expect_equal(nrow(DBI::dbReadTable(con,'possessions')),0L)
  testthat::expect_equal(nrow(DBI::dbReadTable(con,'lineups')),0L)
  reconstruct_season(con,'2024-25')
  testthat::expect_true(all(DBI::dbReadTable(con,'reconstruction_status')$possessions_status=='unresolved'))
})

testthat::test_that('ambiguous lineups, invalid substitutions and minute mismatches are not invented', {
  x<-normalize_bundle(sample_bundle(),'2024-25');id<-x$games$game_id[1]
  g<-x$games[x$games$game_id==id,];e<-x$pbp_events[x$pbp_events$game_id==id,];p<-x$player_box_scores[x$player_box_scores$game_id==id,]
  bad<-p;bad$starter<-FALSE
  testthat::expect_true(any(grepl('starting five',reconstruct_lineups(e,g,bad)$issues)))
  bad<-e;j<-which(grepl('Substitution',bad$event_type))[1];bad$secondary_player_id[j]<-'espn:missing'
  testthat::expect_true(any(grepl('substitution',reconstruct_lineups(bad,g,p)$issues)))
  bad<-p;bad$minutes[1]<-bad$minutes[1]+3
  testthat::expect_true(any(grepl('precision bounds',reconstruct_lineups(e,g,bad)$issues)))
  bad<-e;bad$clock[1]<-'13:00'
  testthat::expect_true(any(grepl('clock',reconstruct_possessions(bad,g,p)$issues)))
})

testthat::test_that('and-one, offensive rebounds and retained free throws have distinct accounting', {
  types<-c('Jump Shot','Shooting Foul','Free Throw - 1 of 1','Jump Shot','Offensive Rebound','Jump Shot','Free Throw - Technical','Jump Shot','Defensive Rebound','Free Throw - 1 of 2','Free Throw - 2 of 2','Offensive Rebound','Lost Ball Turnover','Free Throw - Flagrant 1 of 2','Free Throw - Flagrant 2 of 2','Jump Shot','End Period',rep('End Period',3))
  teams<-c('H','A','H','A','A','A','H','H','A','A','A','A','A','H','H','H',rep(NA_character_,4))
  made<-c(TRUE,FALSE,TRUE,FALSE,FALSE,TRUE,TRUE,FALSE,FALSE,TRUE,FALSE,FALSE,FALSE,TRUE,TRUE,TRUE,rep(FALSE,4))
  value<-c(2,0,1,0,0,2,1,0,0,1,0,0,0,1,1,3,rep(0,4))
  clocks<-c('11:00','11:00','11:00','10:30','10:28','10:20','10:15','10:00','9:58','9:30','9:30','9:28','9:00','8:50','8:50','8:30',rep('0:00',4))
  e<-data.frame(game_id='s',event_id=as.character(seq_along(types)),event_order=seq_along(types),period=c(rep(1L,17),2:4),clock=clocks,event_type=types,description=types,team_id=teams,player_id=ifelse(teams=='H','h','a'),secondary_player_id=NA_character_,tertiary_player_id=NA_character_,type_id=0L,shooting_play=grepl('Jump Shot|Free Throw',types),scoring_play=made,score_value=value,points_attempted=ifelse(grepl('Jump Shot',types),ifelse(value==3,3,2),1),home_score=0L,away_score=0L,dataset_id='synthetic')
  g<-data.frame(game_id='s',home_team_id='H',away_team_id='A',home_score=9L,away_score=3L)
  roster<-data.frame(player_id=c('h','a'),team_id=c('H','A'))
  r<-reconstruct_possessions(e,g,roster)
  testthat::expect_length(r$issues,0L)
  testthat::expect_equal(r$possessions$points,c(3L,2L,0L,1L,3L))
  testthat::expect_equal(sum(r$extra$points),3L)
  testthat::expect_equal(nrow(r$possessions),5L)
  testthat::expect_equal(sum(r$possessions$points)+sum(r$extra$points),12L)
  ot<-e[rep(nrow(e),2),];ot$event_id<-c('ot1','ot2');ot$event_order<-21:22;ot$period<-5L;ot$clock<-c('4:00','0:00');ot$event_type<-c('Jump Shot','End Period');ot$description<-ot$event_type;ot$team_id<-c('H',NA);ot$player_id<-c('h',NA);ot$shooting_play<-c(TRUE,FALSE);ot$scoring_play<-c(TRUE,FALSE);ot$score_value<-c(2L,0L);ot$points_attempted<-c(2L,0L)
  g$home_score<-11L
  overtime<-reconstruct_possessions(rbind(e,ot),g,roster)
  testthat::expect_length(overtime$issues,0L)
  testthat::expect_equal(tail(overtime$possessions$period,1),5L)
})

testthat::test_that('DNP normalization needs explicit evidence and never discards a contribution', {
  b<-sample_bundle();p<-b$player_box$data
  row<-p[1,,drop=FALSE];row$athlete_id<-987654321;row$athlete_display_name<-'Fixture bench player';row$minutes<-NA_real_;row$did_not_play<-FALSE;row$starter<-FALSE;row$reason<-"COACH'S DECISION"
  fields<-c('field_goals_made','field_goals_attempted','three_point_field_goals_made','three_point_field_goals_attempted','free_throws_made','free_throws_attempted','points','assists','turnovers','rebounds')
  row[fields]<-NA_real_
  b$player_box$data<-rbind(p,row)
  x<-normalize_bundle(b,'2024-25')
  testthat::expect_true(x$player_box_scores$did_not_play[x$player_box_scores$player_id=='espn:987654321'])
  b$player_box$data$reason[nrow(b$player_box$data)]<-NA_character_
  x<-normalize_bundle(b,'2024-25')
  testthat::expect_false(x$player_box_scores$did_not_play[x$player_box_scores$player_id=='espn:987654321'])
  b$player_box$data$reason[nrow(b$player_box$data)]<-"COACH'S DECISION";b$player_box$data$points[nrow(b$player_box$data)]<-1
  x<-normalize_bundle(b,'2024-25')
  testthat::expect_false(x$player_box_scores$did_not_play[x$player_box_scores$player_id=='espn:987654321'])
})

testthat::test_that('historical FT encoding and putback order reconcile without inventing missed-shot values', {
  b<-readRDS('data/sample/historical_2016.rds');x<-normalize_bundle(b,'2015-16')
  e<-x$pbp_events;p<-x$player_box_scores;g<-x$games
  f<-event_features(e,p)
  testthat::expect_true(any(f$ft & f$made & e$score_value==0L))
  testthat::expect_true(all(f$points[f$ft & f$made]==1L))
  testthat::expect_true(any(f$fg & !f$made & is.na(f$value)))
  q<-reconcile_pbp_box(e,x$team_box_scores,f);checks<-attr(q,'checks')
  testthat::expect_length(q,0L)
  testthat::expect_true(all(is.na(checks$passed[checks$metric=='fg3a'])))
  testthat::expect_true(all(checks$status[checks$metric=='fg3a']=='unavailable'))
  r<-reconstruct_possessions(e,g,p,f)
  testthat::expect_length(r$issues,0L)
  testthat::expect_true(any(grepl('made putback',r$notes)))
  testthat::expect_equal(sum(r$possessions$points)+sum(r$extra$points),182L)
  l<-reconstruct_lineups(e,g,p,f)
  testthat::expect_length(l$issues,0L)
  testthat::expect_true(all(l$checks$passed))
  con<-connect_warehouse(':memory:');on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  ingest_bundle(con,b,'2015-16');import_reference(con,reference_fixture())
  testthat::expect_equal(nrow(reconcile_game_totals(con)),0L)
  reconstruct_season(con,'2015-16')
  testthat::expect_true(all(DBI::dbReadTable(con,'reconstruction_status')$possessions_status=='reconciled'))
  testthat::expect_true(all(DBI::dbReadTable(con,'pbp_reconciliation_checks')$status[DBI::dbReadTable(con,'pbp_reconciliation_checks')$metric=='fg3a']=='unavailable'))
  testthat::expect_silent(assert_warehouse_integrity(con))
})

testthat::test_that('independent turnovers come from player records across changing team-total conventions', {
  ref<-normalize_reference(load_reference_fixture())
  cle<-ref[ref$source_game_id=='0021500002' & ref$team_id=='espn:5',]
  testthat::expect_equal(cle$reported_turnovers,11L)
  testthat::expect_equal(cle$turnovers,10L)
  testthat::expect_equal(cle$total_turnovers,11L)
  current<-ref[ref$source_game_id=='0022401185' & ref$team_id=='espn:13',]
  testthat::expect_equal(current$reported_turnovers,12L)
  testthat::expect_equal(current$turnovers,12L)
  testthat::expect_equal(current$total_turnovers,13L)
})
