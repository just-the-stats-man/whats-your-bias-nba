require_fields <- function(data, fields, dataset) {
  missing <- setdiff(fields, names(data))
  if (length(missing)) stop('Source schema changed: ', dataset, ' missing ', paste(missing, collapse = ', '))
}
deduplicate <- function(data, keys) {
  data <- unique(data)
  if (anyNA(data[keys]) || anyDuplicated(data[keys])) stop('Missing or conflicting duplicate identifiers')
  data
}
provider_id <- function(x) ifelse(is.na(x) | x == '', NA_character_, paste0('espn:', format(x, scientific = FALSE, trim = TRUE)))

normalize_bundle <- function(bundle, season, game_ids = NULL) {
  # RDS restores integer64 classes without loading their S3 conversion methods.
  # Convert explicitly to preserve exact 64-bit event IDs across fresh sessions.
  bundle <- lapply(bundle,function(item) {
    item$data[] <- lapply(item$data,function(col) if(inherits(col,'integer64')) bit64::as.character.integer64(col) else col)
    item
  })
  s <- bundle$schedules$data; p <- bundle$player_box$data; t <- bundle$team_box$data; e <- bundle$pbp$data
  require_fields(s, c('game_id','season','season_type','game_date','home_id','away_id','home_score','away_score','status_type_completed','home_abbreviation','away_abbreviation','home_display_name','away_display_name'), 'schedules')
  require_fields(p, c('game_id','athlete_id','athlete_display_name','team_id','minutes','field_goals_made','field_goals_attempted','three_point_field_goals_made','three_point_field_goals_attempted','free_throws_made','free_throws_attempted','points','assists','turnovers','rebounds','did_not_play'), 'player_box')
  require_fields(t, c('game_id','team_id','team_score','field_goals_made','field_goals_attempted','three_point_field_goals_made','three_point_field_goals_attempted','free_throws_made','free_throws_attempted','assists','turnovers'), 'team_box')
  require_fields(e, c('game_id','id','game_play_number','period_number','clock_display_value','type_text','text','team_id','athlete_id_1','home_score','away_score','shooting_play','scoring_play','coordinate_x','coordinate_y'), 'pbp')
  # Known historical variant: absence of attempt value prevents reliable
  # separation of field goals and free throws. Preserve PBP, omit derived shots.
  if (!'points_attempted' %in% names(e)) {
    e$points_attempted <- rep(NA_integer_,nrow(e))
    message('Historical schema lacks points_attempted; derived shots unavailable')
  }
  if (any(s$season != season_end(season), na.rm = TRUE)) stop('Incorrect source season')
  s <- s[eligible_schedule(s), ]
  if (!is.null(game_ids)) s <- s[as.character(s$game_id) %in% game_ids, ]
  if (!nrow(s)) stop('No completed regular-season or playoff games selected')
  ids <- as.character(s$game_id)
  p <- p[as.character(p$game_id) %in% ids, ]; t <- t[as.character(t$game_id) %in% ids, ]; e <- e[as.character(e$game_id) %in% ids, ]
  hashes <- vapply(bundle,function(item) file_sha256(item$path),character(1))
  ds <- function(kind) paste0('sdv:', kind, ':', season, ':', hashes[[kind]])
  identities <- unique(rbind(data.frame(team_id=provider_id(s$home_id),season=season,abbreviation=s$home_abbreviation,name=s$home_display_name), data.frame(team_id=provider_id(s$away_id),season=season,abbreviation=s$away_abbreviation,name=s$away_display_name)))
  # Names can vary by game; retain the latest encountered provider spelling per identifier.
  players <- data.frame(player_id=provider_id(p$athlete_id),name=p$athlete_display_name,search_name=normalize_name(p$athlete_display_name))
  players <- players[!duplicated(players$player_id), ]
  games <- data.frame(game_id=as.character(s$game_id),season=season,season_type=as.integer(s$season_type),game_date=as.Date(s$game_date),home_team_id=provider_id(s$home_id),away_team_id=provider_id(s$away_id),home_score=as.integer(s$home_score),away_score=as.integer(s$away_score),completed=as.logical(s$status_type_completed),dataset_id=ds('schedules'))
  pb <- data.frame(game_id=as.character(p$game_id),player_id=provider_id(p$athlete_id),team_id=provider_id(p$team_id),minutes=as.numeric(p$minutes),fgm=as.integer(p$field_goals_made),fga=as.integer(p$field_goals_attempted),fg3m=as.integer(p$three_point_field_goals_made),fg3a=as.integer(p$three_point_field_goals_attempted),ftm=as.integer(p$free_throws_made),fta=as.integer(p$free_throws_attempted),points=as.integer(p$points),assists=as.integer(p$assists),turnovers=as.integer(p$turnovers),rebounds=as.integer(p$rebounds),did_not_play=as.logical(p$did_not_play),dataset_id=ds('player_box'))
  tb <- data.frame(game_id=as.character(t$game_id),team_id=provider_id(t$team_id),points=as.integer(t$team_score),fgm=as.integer(t$field_goals_made),fga=as.integer(t$field_goals_attempted),fg3m=as.integer(t$three_point_field_goals_made),fg3a=as.integer(t$three_point_field_goals_attempted),ftm=as.integer(t$free_throws_made),fta=as.integer(t$free_throws_attempted),assists=as.integer(t$assists),turnovers=as.integer(t$turnovers),dataset_id=ds('team_box'))
  events <- data.frame(game_id=as.character(e$game_id),event_id=as.character(e$id),event_order=as.integer(e$game_play_number),period=as.integer(e$period_number),clock=e$clock_display_value,event_type=e$type_text,description=e$text,team_id=provider_id(e$team_id),player_id=provider_id(e$athlete_id_1),home_score=as.integer(e$home_score),away_score=as.integer(e$away_score),dataset_id=ds('pbp'))
  events$player_id[!events$player_id %in% players$player_id] <- NA_character_
  # Field-goal attempts only: ESPN shooting_play also includes free throws.
  shot <- e$shooting_play %in% TRUE & e$points_attempted %in% c(2,3)
  shots <- data.frame(game_id=as.character(e$game_id[shot]),event_id=as.character(e$id[shot]),player_id=events$player_id[shot],team_id=events$team_id[shot],points_attempted=as.integer(e$points_attempted[shot]),made=as.logical(e$scoring_play[shot]),x=as.numeric(e$coordinate_x[shot]),y=as.numeric(e$coordinate_y[shot]),coordinate_system=rep('sportsdataverse ESPN transformed; uncalibrated',sum(shot)),observation_type=rep('provider_attributed',sum(shot)),dataset_id=rep(ds('pbp'),sum(shot)))
  shots$x[abs(shots$x)>100] <- NA_real_; shots$y[abs(shots$y)>100] <- NA_real_
  subs <- events[grepl('substitution', events$event_type, ignore.case=TRUE),c('game_id','event_id','description','dataset_id')]
  list(seasons=data.frame(season=season,end_year=season_end(season)),teams=unique(data.frame(team_id=identities$team_id,provider='espn')),team_identities=identities,players=players,player_identifiers=data.frame(provider='espn',provider_id=sub('espn:','',players$player_id),player_id=players$player_id),games=games,player_box_scores=pb,team_box_scores=tb,pbp_events=events,shot_attempts=shots,substitutions=subs)
}
