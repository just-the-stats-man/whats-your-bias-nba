withr::local_dir(Sys.getenv('WYB_ROOT'))
fixture <- function() readRDS('data/sample/bundle.rds')
testthat::test_that('real sample passes validation, joins, queries and repeat ingestion', {
  con <- connect_warehouse(':memory:'); on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  b <- fixture()
  testthat::expect_silent(ingest_bundle(con,b,'2024-25'))
  before <- DBI::dbGetQuery(con,'SELECT * FROM player_box_scores ORDER BY game_id,player_id')
  ingest_bundle(con,b,'2024-25')
  testthat::expect_equal(DBI::dbGetQuery(con,'SELECT * FROM player_box_scores ORDER BY game_id,player_id'),before)
  g <- get_player_games('Luka Doncic','2024-25',con)
  testthat::expect_equal(nrow(g),3)
  testthat::expect_gt(nrow(get_game_pbp(g$game_id[1],con)),300)
  testthat::expect_true(all(grepl('^[0-9]+$',get_game_pbp(g$game_id[1],con)$event_id)))
  testthat::expect_gt(nrow(get_player_shots('Luka Doncic','2024-25',con)),0)
  testthat::expect_true(is.finite(offensive_efficiency(g)$true_shooting))
  missing <- g; missing$fga[1]<-NA_integer_
  testthat::expect_error(offensive_efficiency(missing),'missing statistics')
  dnp <- g; dnp$did_not_play[1]<-TRUE
  testthat::expect_equal(offensive_efficiency(dnp)$games,2L)
  testthat::expect_error(get_team_lineups('LAL','2024-25',con),'Lineups unavailable')
  testthat::expect_error(get_player_salary('Luka Doncic','2024-25',con),'Salary unavailable')
  testthat::expect_error(get_player_games('Nobody',con=con),'Player unavailable')
  testthat::expect_error(get_game_pbp('missing',con),'unavailable')
  testthat::expect_error(DBI::dbExecute(con,"INSERT INTO seasons VALUES ('2024-25',2025)"),'Duplicate key')
  dest <- tempfile(); export_parquet(con,dest)
  testthat::expect_equal(nrow(arrow::read_parquet(file.path(dest,'games.parquet'))),3)
})
testthat::test_that('identifier, schema, team, date, score and event defects fail', {
  x <- normalize_bundle(fixture(),'2024-25')
  testthat::expect_silent(assert_quality(x))
  bad <- x; bad$games <- rbind(bad$games,bad$games[1,]); testthat::expect_error(assert_quality(bad),'duplicate')
  bad <- x; bad$players$player_id[1]<-NA_character_; testthat::expect_error(assert_quality(bad),'missing identifiers')
  bad <- x; bad$games$game_date[1]<-as.Date('1900-01-01'); testthat::expect_error(assert_quality(bad),'dates')
  bad <- x; bad$games$season[1]<-'2020-21'; testthat::expect_error(assert_quality(bad),'season mapping')
  bad <- x; bad$player_box_scores$team_id[1]<-'espn:999'; testthat::expect_error(assert_quality(bad),'team assignments')
  bad <- x; bad$player_box_scores$points[1]<-999L; testthat::expect_error(assert_quality(bad),'scoring totals')
  bad <- x; bad$players<-bad$players[-1,]; testthat::expect_error(assert_quality(bad),'broken player joins')
  bad <- x; bad$pbp_events<-bad$pbp_events[-1,]; testthat::expect_error(assert_quality(bad),'event order')
  bad <- x; bad$pbp_events<-bad$pbp_events[0,]; testthat::expect_error(assert_quality(bad),'missing play-by-play')
  b <- fixture(); b$player_box$data$points<-NULL; testthat::expect_error(normalize_bundle(b,'2024-25'),'schema changed')
  testthat::expect_error(season_end('2024-26'),'season mapping')
  testthat::expect_error(deduplicate(data.frame(id=c(1,1),value=c(1,2)),'id'),'conflicting duplicate')
})
testthat::test_that('failed ingestion is logged and leaves facts unchanged', {
  con<-connect_warehouse(':memory:'); on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  b<-fixture(); b$player_box$data$points[1]<-999L
  testthat::expect_error(ingest_bundle(con,b,'2024-25'),'quality failed')
  testthat::expect_equal(DBI::dbGetQuery(con,'SELECT count(*) n FROM games')$n,0)
  testthat::expect_equal(DBI::dbGetQuery(con,'SELECT status FROM ingestion_runs')$status,'failed')
})
testthat::test_that('cache avoids network and API failures propagate without corrupting cache', {
  path<-tempfile(); saveRDS(list(ok=TRUE),path)
  testthat::expect_equal(fetch_cached('https://example.invalid',path,perform=function(...)stop('network called')),path)
  testthat::expect_error(fetch_cached('https://example.invalid',tempfile(),perform=function(...)stop('HTTP 503')),'HTTP 503')
  testthat::expect_error(fetch_cached('https://example.invalid',path,refresh=TRUE,perform=function(...)stop('HTTP 429')),'HTTP 429')
  testthat::expect_equal(readRDS(path),list(ok=TRUE))
})

testthat::test_that('incremental updates skip completed games', {
  con<-connect_warehouse(':memory:'); on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  ingest <- ingest_season
  scope <- new.env(parent=environment(ingest))
  scope$fetch_season <- function(...) fixture()
  environment(ingest) <- scope
  ingest(con,'2024-25')
  attempts <- nrow(DBI::dbReadTable(con,'ingestion_runs'))
  testthat::expect_equal(ingest(con,'2024-25'),'Already up to date')
  testthat::expect_equal(nrow(DBI::dbReadTable(con,'ingestion_runs')),attempts)
})

testthat::test_that('historical PBP without attempt values never fabricates shots', {
  b<-fixture(); b$pbp$data$points_attempted<-NULL
  testthat::expect_message(x<-normalize_bundle(b,'2024-25'),'derived shots unavailable')
  testthat::expect_equal(nrow(x$shot_attempts),0L)
  testthat::expect_gt(nrow(x$pbp_events),0L)
  testthat::expect_silent(assert_quality(x))
})

testthat::test_that('All-Star showcase teams are excluded despite regular season type', {
  s<-fixture()$schedules$data
  testthat::expect_true(all(eligible_schedule(s)))
  s$home_id[1]<-130579L
  testthat::expect_false(eligible_schedule(s)[1])
})

testthat::test_that('database write failure rolls back the complete fact transaction', {
  con<-connect_warehouse(':memory:'); on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  DBI::dbExecute(con,'DROP TABLE pbp_events')
  testthat::expect_error(ingest_bundle(con,fixture(),'2024-25'),'pbp_events')
  testthat::expect_equal(nrow(DBI::dbReadTable(con,'games')),0L)
  testthat::expect_equal(nrow(DBI::dbReadTable(con,'datasets')),0L)
  testthat::expect_equal(DBI::dbReadTable(con,'ingestion_runs')$status,'failed')
})
