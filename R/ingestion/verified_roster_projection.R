roster_projection_method <- function() {
  inputs<-c(list(phase4_shot_method()),lapply(c('verified_roster_team_assignments','prepare_verified_roster_projection','historical_box_sql'),function(name)body(get(name,mode='function',inherits=TRUE))),list(readLines('config/team_crosswalk.csv',warn=FALSE)))
  paste0('terminal-roster-shots-v1-',substr(digest::digest(inputs,algo='sha256'),1,16))
}

verified_roster_team_assignments <- function(raw,games,links,roster,player_links,team_map) {
  raw$nba_game_id<-paste0('nba:',sprintf('%010.0f',as.numeric(raw$gameId)));raw$nba_player_id<-paste0('nba:',as.character(raw$personId))
  gi<-match(raw$nba_game_id,games$game_id)
  valid<-!is.na(gi)&raw$home%in%c('0','1')&is.na(raw$playerteamId)&is.na(raw$opponentteamId)
  valid<-valid & !duplicated(links$nba_game_id)[match(raw$nba_game_id,links$nba_game_id)] & !duplicated(links$nba_game_id,fromLast=TRUE)[match(raw$nba_game_id,links$nba_game_id)]
  game<-links$espn_game_id[match(raw$nba_game_id,links$nba_game_id)]
  unique_players<-player_links[!duplicated(player_links$nba_player_id),c('nba_player_id','player_id')]
  bad_nba<-names(which(vapply(split(player_links$player_id,player_links$nba_player_id),function(x)length(unique(x)),integer(1))!=1L))
  bad_espn<-names(which(vapply(split(player_links$nba_player_id,player_links$player_id),function(x)length(unique(x)),integer(1))!=1L))
  player<-unique_players$player_id[match(raw$nba_player_id,unique_players$nba_player_id)]
  key<-paste(roster$game_id,roster$player_id);ri<-match(paste(game,player),key)
  valid<-valid & !is.na(ri)&!raw$nba_player_id%in%bad_nba&!player%in%bad_espn&!duplicated(key)[ri]&!duplicated(key,fromLast=TRUE)[ri]&!roster$did_not_play[ri]%in%TRUE
  team<-ifelse(raw$home=='1',games$home_team_id[gi],games$away_team_id[gi])
  expected_team<-paste0('nba:',team_map$nba_id[match(sub('espn:','',roster$team_id[ri]),team_map$espn_id)])
  valid<-valid & !is.na(team)&team==expected_team
  metrics<-historical_metrics();fields<-c('fgm','fga','fg3m','fg3a','ftm','fta','points','assists','turnovers','rebounds')
  counts<-list()
  for(m in fields) {
    value<-suppressWarnings(as.numeric(raw[[metrics$source_column[match(m,metrics$metric)]]]))
    valid<-valid & !is.na(value)&is.finite(value)&value>=0&value==floor(value)&!is.na(roster[[m]][ri])&value==roster[[m]][ri]
    counts[[m]]<-value
  }
  minutes<-suppressWarnings(as.numeric(raw[[metrics$source_column[match('minutes',metrics$metric)]]]))
  known<-!is.na(minutes)&!is.na(roster$minutes[ri]);tol<-ifelse(abs(minutes-round(minutes))<1e-8|abs(roster$minutes[ri]-round(roster$minutes[ri]))<1e-8,1,1.01/60)
  valid<-valid & known & abs(minutes-roster$minutes[ri])<=tol
  valid[is.na(valid)]<-FALSE
  result<-data.frame(source_row=raw$source_row[valid],nba_game_id=raw$nba_game_id[valid],nba_player_id=raw$nba_player_id[valid],raw_home=raw$home[valid],nba_team_id=team[valid],game_id=game[valid],player_id=player[valid],team_id=roster$team_id[ri[valid]],minutes=minutes[valid],minute_tolerance=tol[valid],counts_match=rep(TRUE,sum(valid)),minutes_match=rep(TRUE,sum(valid)))
  for(m in fields)result[[m]]<-counts[[m]][valid]
  result
}

prepare_verified_roster_projection <- function(con,season='2021-22') {
  source<-DBI::dbGetQuery(con,"SELECT * FROM historical_snapshots WHERE kind='player'");stopifnot(nrow(source)==1L,file_sha256(source$path)==source$sha256)
  sql<-paste0('CREATE OR REPLACE TEMP TABLE _phase4_native_player AS WITH raw AS (SELECT row_number() OVER () source_row,* FROM read_csv(',DBI::dbQuoteString(con,source$path),",all_varchar=TRUE)) SELECT raw.* FROM raw JOIN historical_games g ON 'nba:'||",historical_sql_id('raw.gameId'),"=g.game_id WHERE g.season=",DBI::dbQuoteString(con,season))
  DBI::dbExecute(con,sql);raw<-DBI::dbReadTable(con,'_phase4_native_player')
  games<-DBI::dbGetQuery(con,'SELECT * FROM historical_games WHERE season=?',params=list(season))
  links<-DBI::dbReadTable(con,'historical_game_links');roster<-DBI::dbGetQuery(con,'SELECT p.* FROM player_box_scores p JOIN games g USING(game_id) WHERE g.season=?',params=list(season));players<-DBI::dbReadTable(con,'sdv_nba_player_links')
  evidence<-verified_roster_team_assignments(raw,games,links,roster,players,utils::read.csv('config/team_crosswalk.csv',colClasses='character'))
  # Fill only the missing native team FK in a temporary working projection.
  # Home, opponent, all statistics and every raw file remain unchanged.
  j<-match(raw$source_row,evidence$source_row);raw$playerteamId[!is.na(j)]<-sub('nba:','',evidence$nba_team_id[j[!is.na(j)]])
  DBI::dbWriteTable(con,'_history_player',raw,temporary=TRUE,overwrite=TRUE)
  normalized<-DBI::dbGetQuery(con,historical_box_sql(con,'player',source$snapshot_id,season))
  old<-DBI::dbGetQuery(con,'SELECT * FROM historical_player_boxes WHERE season=?',params=list(season))
  old_j<-match(normalized$source_row,old$source_row)
  stopifnot(!anyNA(old_j),all(normalized$game_id==old$game_id[old_j]),all(normalized$player_id==old$player_id[old_j]))
  keep<-normalized$source_row%in%evidence$source_row & normalized$validation_status=='observed' & old$validation_status[old_j]!='observed'
  rows<-normalized[keep,];evidence<-evidence[evidence$source_row%in%rows$source_row,]
  rows$identity_evidence<-'reconstructed team FK: recorded home flag + unique game + verified cross-provider player/roster + all ten counts and minutes agree'
  list(rows=rows,evidence=evidence,source=source,method=roster_projection_method())
}

install_verified_roster_projection <- function(con,projection) {
  DBI::dbWriteTable(con,'_phase4_verified_player_boxes',projection$rows,temporary=TRUE,overwrite=TRUE)
  # Only this staging connection shadows the baseline; the frozen table stays.
  DBI::dbExecute(con,'CREATE OR REPLACE TEMP VIEW historical_player_boxes AS SELECT p.* FROM baseline.main.historical_player_boxes p WHERE NOT EXISTS(SELECT 1 FROM _phase4_verified_player_boxes q WHERE p.snapshot_id=q.snapshot_id AND p.source_row=q.source_row) UNION ALL SELECT * FROM _phase4_verified_player_boxes')
}
