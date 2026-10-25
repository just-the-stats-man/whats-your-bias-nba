shot_reference_observations <- function(input,season) {
  team<-utils::read.csv('config/team_crosswalk.csv',colClasses='character')
  DBI::dbWriteTable(input,'_shot_team_map',data.frame(nba_team=paste0('nba:',team$nba_id),team_id=paste0('espn:',team$espn_id)),temporary=TRUE,overwrite=TRUE)
  nba<-DBI::dbGetQuery(input,"SELECT l.espn_game_id game_id,p.game_id nba_game_id,p.* EXCLUDE(game_id),m.team_id canonical_team,n.name FROM historical_player_boxes p JOIN historical_game_links l ON p.game_id=l.nba_game_id JOIN historical_players n USING(player_id) JOIN _shot_team_map m ON p.team_id=m.nba_team WHERE p.season=? AND p.validation_status='observed'",params=list(season))
  espn<-DBI::dbGetQuery(input,'SELECT p.*,n.name FROM player_box_scores p JOIN games g USING(game_id) JOIN players n USING(player_id) WHERE g.season=?',params=list(season))
  if(!nrow(nba) || !nrow(espn))return(data.frame())
  # Unicode transliteration is explicit, never fuzzy. Require unique full-name,
  # game/team keys AND agreement of every recorded counting statistic.
  a<-paste(nba$game_id,nba$canonical_team,normalize_name(nba$name));b<-paste(espn$game_id,espn$team_id,normalize_name(espn$name))
  j<-match(a,b)
  valid<-!is.na(j) & !duplicated(a) & !duplicated(a,fromLast=TRUE) & !duplicated(b)[j] & !duplicated(b,fromLast=TRUE)[j]
  for(m in c('fgm','fga','fg3m','fg3a','ftm','fta','points','assists','turnovers','rebounds'))valid<-valid & !is.na(nba[[m]]) & nba[[paste0(m,'_status')]]=='observed' & !is.na(espn[[m]][j]) & nba[[m]]==espn[[m]][j]
  known<-!is.na(nba$minutes) & !is.na(espn$minutes[j])
  tolerance<-ifelse(abs(nba$minutes-round(nba$minutes))<1e-8 | abs(espn$minutes[j]-round(espn$minutes[j]))<1e-8,1,1.01/60)
  valid<-valid & (!known | abs(nba$minutes-espn$minutes[j])<=tolerance)
  valid[is.na(valid)]<-FALSE
  links<-data.frame(game_id=nba$game_id[valid],nba_game_id=nba$nba_game_id[valid],nba_player_id=nba$player_id[valid],player_id=espn$player_id[j[valid]],team_id=nba$canonical_team[valid],nba_name=nba$name[valid],espn_name=espn$name[j[valid]],evidence='unique transliterated full name/game/mapped team; all recorded counts agree',stringsAsFactors=FALSE)
  if(!nrow(links))return(data.frame())
  DBI::dbWriteTable(input,'_shot_player_links',links,temporary=TRUE,overwrite=TRUE)
  shots<-DBI::dbGetQuery(input,"WITH qualified AS (SELECT game_id FROM historical_event_checks WHERE season=? GROUP BY game_id HAVING count(*)=10 AND bool_and(status='reconstructed')) SELECT l.game_id,l.player_id,l.team_id,e.period,e.clock,s.made,s.points_attempted,s.snapshot_id,s.source_row,e.event_id nba_event_id,l.nba_game_id,l.nba_player_id,l.evidence FROM historical_shots s JOIN historical_events e USING(snapshot_id,source_row) JOIN qualified q ON s.game_id=q.game_id JOIN _shot_player_links l ON s.game_id=l.nba_game_id AND s.player_id=l.nba_player_id WHERE s.season=? AND e.season=? AND s.points_status='observed' AND s.made IS NOT NULL",params=list(season,season,season))
  if(!nrow(shots))return(shots)
  iso<-grepl('^PT',shots$clock)
  clocks<-shots$clock
  clocks[iso]<-sub('^PT([0-9]+)M([0-9.]+)S$','\\1:\\2',clocks[iso])
  shots$clock_seconds<-vapply(strsplit(clocks,':',fixed=TRUE),function(v)if(length(v)==2L)as.numeric(v[1])*60+as.numeric(v[2]) else NA_real_,numeric(1))
  shots<-shots[!is.na(shots$clock_seconds),,drop=FALSE]
  attr(shots,'player_links')<-links
  shots
}
