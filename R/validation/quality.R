table_keys <- list(sources='source_id',datasets='dataset_id',seasons='season',teams='team_id',team_identities=c('team_id','season'),players='player_id',player_identifiers=c('provider','provider_id'),games='game_id',player_box_scores=c('game_id','player_id'),team_box_scores=c('game_id','team_id'),pbp_events=c('game_id','event_id'),shot_attempts=c('game_id','event_id'),substitutions=c('game_id','event_id'))

quality_report <- function(x) {
  issues <- data.frame(check=character(),severity=character(),count=integer())
  add <- function(check, n, severity='error') {
    if (n > 0) issues[nrow(issues)+1L, ] <<- list(check,severity,as.integer(n))
  }
  for (table in intersect(names(x), names(table_keys))) {
    key <- x[[table]][table_keys[[table]]]
    add(paste(table,'missing identifiers'),sum(!complete.cases(key)))
    add(paste(table,'duplicate records'),sum(duplicated(key)))
  }
  if (nrow(issues)) return(issues)
  g <- x$games; p <- x$player_box_scores; t <- x$team_box_scores; e <- x$pbp_events
  add('invalid game dates',sum(is.na(g$game_date) | g$game_date < as.Date('1946-01-01') | g$game_date > Sys.Date()))
  # Calendar windows include the pandemic restart in summer 2020.
  end <- as.integer(substr(g$season,1,4))+1L
  add('incorrect season mapping',sum(g$game_date < as.Date(sprintf('%d-07-01',end-1L)) | g$game_date > as.Date(sprintf('%d-10-15',end)),na.rm=TRUE))
  add('same home and away team',sum(g$home_team_id==g$away_team_id))
  add('broken game team joins',sum(!g$home_team_id %in% x$teams$team_id)+sum(!g$away_team_id %in% x$teams$team_id))
  add('broken player joins',sum(!p$player_id %in% x$players$player_id))
  for (table in c('player_box_scores','team_box_scores','pbp_events','shot_attempts','substitutions')) add(paste(table,'broken game joins'),sum(!x[[table]]$game_id %in% g$game_id))
  event_keys <- paste(e$game_id,e$event_id,sep=':')
  for (table in c('shot_attempts','substitutions')) add(paste(table,'broken event joins'),sum(!paste(x[[table]]$game_id,x[[table]]$event_id,sep=':') %in% event_keys))
  add('broken event player joins',sum(!is.na(e$player_id) & !e$player_id %in% x$players$player_id))
  add('broken identifier joins',sum(!x$player_identifiers$player_id %in% x$players$player_id))
  for (table in c('player_box_scores','team_box_scores')) {
    z <- x[[table]]; j <- match(z$game_id,g$game_id)
    add(paste(table,'inconsistent team assignments'),sum(!is.na(j) & !(z$team_id==g$home_team_id[j] | z$team_id==g$away_team_id[j])))
    add(paste(table,'inconsistent scoring totals'),sum(z$points != 2*z$fgm+z$fg3m+z$ftm,na.rm=TRUE))
    add(paste(table,'made exceeds attempted'),sum(z$fgm>z$fga | z$fg3m>z$fg3a | z$ftm>z$fta,na.rm=TRUE))
  }
  add('missing player statistics',sum(!p$did_not_play & !complete.cases(p[c('fgm','fga','fg3m','ftm','fta','points')]),na.rm=TRUE))
  for (id in g$game_id) {
    tg <- t[t$game_id==id, ]; pg <- p[p$game_id==id, ]; eg <- e[e$game_id==id, ]; gg <- g[g$game_id==id, ]
    add('missing team box scores',as.integer(nrow(tg)!=2L))
    add('missing play-by-play',as.integer(nrow(eg)==0L))
    if (nrow(eg)) {
      add('duplicated event order',sum(duplicated(eg$event_order)))
      add('noncontiguous event order',as.integer(!identical(sort(eg$event_order),seq_len(nrow(eg)))))
      last <- eg[which.max(eg$event_order), ]
      add('PBP final score differs from schedule',as.integer(last$home_score != gg$home_score | last$away_score != gg$away_score),'warning')
    }
    for (team in tg$team_id) {
      total <- sum(pg$points[pg$team_id==team],na.rm=TRUE)
      add('player points differ from team total',as.integer(total != tg$points[tg$team_id==team]))
      official <- if (team==gg$home_team_id) gg$home_score else gg$away_score
      add('team points differ from schedule',as.integer(tg$points[tg$team_id==team] != official))
    }
  }
  issues
}

assert_quality <- function(x) {
  report <- quality_report(x)
  if (any(report$severity=='error')) stop('Data quality failed: ',paste(unique(report$check[report$severity=='error']),collapse='; '))
  invisible(report)
}
