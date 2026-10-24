resolve_player <- function(con,player) {
  p <- DBI::dbGetQuery(con,'SELECT player_id FROM players WHERE player_id=? OR search_name=?',params=list(player,normalize_name(player)))$player_id
  if (!length(p)) stop('Player unavailable in local warehouse; ingest their seasons first: ',player)
  if (length(p)>1L) stop('Ambiguous name; use a stable player_id')
  p
}
get_player_games <- function(player,seasons=NULL,con) {
  id <- resolve_player(con,player)
  q <- dplyr::tbl(con,'player_box_scores') |>
    dplyr::filter(.data$player_id==id) |>
    dplyr::inner_join(dplyr::tbl(con,'games'),by='game_id',suffix=c('','_game'))
  if (!is.null(seasons)) q <- dplyr::filter(q,.data$season %in% seasons)
  out <- dplyr::collect(dplyr::arrange(q,.data$game_date))
  if (!nrow(out)) stop('Requested seasons unavailable locally; run ingestion first')
  out
}
get_game_pbp <- function(game_id,con) {
  out <- DBI::dbGetQuery(con,'SELECT * FROM pbp_events WHERE game_id=? ORDER BY event_order',params=list(game_id))
  if (!nrow(out)) stop('Play-by-play unavailable locally for this game; ingest the game season')
  out
}
get_player_shots <- function(player,season,con) {
  id <- resolve_player(con,player)
  out <- dplyr::tbl(con,'shot_attempts') |>
    dplyr::inner_join(dplyr::tbl(con,'games'),by='game_id',suffix=c('','_game')) |>
    dplyr::filter(.data$player_id==id,.data$season==!!season) |>
    dplyr::collect()
  if (!nrow(out)) stop('Shot attempts unavailable for this player/season; ingest PBP first')
  out
}
get_team_lineups <- function(team,season,con) {
  out <- DBI::dbGetQuery(con,'SELECT l.* FROM lineups l JOIN games g USING(game_id) JOIN team_identities t ON l.team_id=t.team_id AND g.season=t.season WHERE t.abbreviation=? AND g.season=?',params=list(team,season))
  if (!nrow(out)) stop('Lineups unavailable: substitutions alone do not establish all five players; a validated lineup source is required')
  out
}
get_player_salary <- function(player,season,con) {
  id <- resolve_player(con,player)
  out <- DBI::dbGetQuery(con,'SELECT s.* FROM salaries s JOIN contracts c USING(contract_id) WHERE c.player_id=? AND s.season=?',params=list(id,season))
  if (!nrow(out)) stop('Salary unavailable: no licensed contract source has been imported')
  out
}
offensive_efficiency <- function(games) {
  games <- games[!games$did_not_play %in% TRUE, , drop=FALSE]
  fields <- c('points','fgm','fga','fg3m','fta','assists','turnovers')
  if (anyNA(games[fields])) stop('Efficiency unavailable: missing statistics for a non-DNP game')
  totals <- colSums(as.data.frame(games)[fields])
  data.frame(games=nrow(games),points=totals[['points']],efg=if(totals[['fga']]>0) (totals[['fgm']]+0.5*totals[['fg3m']])/totals[['fga']] else NA_real_,true_shooting=if(totals[['fga']]+0.44*totals[['fta']]>0) totals[['points']]/(2*(totals[['fga']]+0.44*totals[['fta']])) else NA_real_,assists=totals[['assists']],turnovers=totals[['turnovers']])
}
