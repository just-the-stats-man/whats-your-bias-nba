source('scripts/load.R')
folder<-'data/processed/phase4';out<-'docs/phase4';dir.create(out,recursive=TRUE,showWarnings=FALSE)
con<-DBI::dbConnect(duckdb::duckdb(),dbdir=file.path(folder,'baseline.duckdb'),read_only=TRUE)
tryCatch({
  DBI::dbExecute(con,'SET threads=4');DBI::dbExecute(con,"SET memory_limit='3GB'")
  queries<-list(
    shot_failures="SELECT season,metric,status,count(*) team_checks,count(DISTINCT game_id) games FROM shot_recovery_checks GROUP BY ALL ORDER BY ALL",
    shot_evidence="SELECT c.season,count(*) candidates,count(*) FILTER(WHERE g.game_id IS NOT NULL) canonical_game_candidates,count(*) FILTER(WHERE g.game_id IS NOT NULL AND c.certification_status!='certified') noncertified_canonical_candidates,count(*) FILTER(WHERE g.game_id IS NOT NULL AND c.certification_status!='certified' AND c.points_attempted IS NULL) noncertified_unknown_value,count(*) FILTER(WHERE g.game_id IS NOT NULL AND c.certification_status!='certified' AND c.player_id IS NULL) noncertified_unknown_shooter,count(*) FILTER(WHERE g.game_id IS NOT NULL AND c.certification_status!='certified' AND c.made IS NULL) noncertified_unknown_outcome,count(*) FILTER(WHERE g.game_id IS NOT NULL AND c.certification_status!='certified' AND c.coordinate_status!='observed') noncertified_missing_or_invalid_coordinates FROM shot_recovery_candidates c LEFT JOIN games g USING(game_id) GROUP BY c.season ORDER BY c.season",
    shot_recovery_bounds="WITH q AS (SELECT game_id,bool_and(status='match') FILTER(WHERE metric IN ('fga','fgm')) attempt_outcome_match,bool_and(status='match') FILTER(WHERE metric IN ('fg3a','fg3m')) three_match FROM shot_recovery_checks GROUP BY game_id) SELECT c.season,q.attempt_outcome_match,q.three_match,count(DISTINCT c.game_id) games,count(*) observed_attempts,count(*) FILTER(WHERE c.points_attempted IS NULL) unclassified_attempts FROM shot_recovery_candidates c JOIN games g USING(game_id) JOIN q USING(game_id) WHERE c.certification_status!='certified' GROUP BY ALL ORDER BY ALL",
    missing_pbp="SELECT g.season,g.season_type,count(*) canonical_games_without_pbp,sum(t.fga) box_fga FROM games g LEFT JOIN (SELECT game_id,sum(fga) fga FROM team_box_scores GROUP BY game_id) t USING(game_id) WHERE NOT EXISTS(SELECT 1 FROM pbp_events e WHERE e.game_id=g.game_id) GROUP BY ALL ORDER BY ALL",
    identities="SELECT 'sdv_nba_player_links' AS observation_family,count(*) AS n_rows,count(DISTINCT player_id) espn_players,count(DISTINCT nba_player_id) nba_players FROM sdv_nba_player_links",
    substitution_gaps="SELECT g.season,count(*) substitution_events,count(*) FILTER(WHERE e.player_id IS NULL OR e.secondary_player_id IS NULL) missing_role_ids,count(*) FILTER(WHERE e.description LIKE '% enters the game for %') explicit_role_description,count(DISTINCT e.game_id) affected_games FROM pbp_events e JOIN games g USING(game_id) JOIN reconstruction_status r USING(game_id) WHERE lower(e.event_type) LIKE '%substitution%' AND r.lineups_status!='reconciled' GROUP BY g.season ORDER BY g.season",
    lebron="SELECT g.season,count(*) box_games,count(*) FILTER(WHERE p.did_not_play IS DISTINCT FROM TRUE AND p.minutes>0) positive_minute_games,count(*) FILTER(WHERE r.possessions_status='reconciled' AND p.minutes>0) possession_games,count(*) FILTER(WHERE r.lineups_status='reconciled' AND p.minutes>0) lineup_games FROM player_box_scores p JOIN games g USING(game_id) LEFT JOIN reconstruction_status r USING(game_id) WHERE p.player_id='espn:1966' GROUP BY g.season ORDER BY g.season")
  for(name in names(queries))utils::write.csv(DBI::dbGetQuery(con,queries[[name]]),file.path(out,paste0(name,'.csv')),row.names=FALSE,na='')
  tables<-DBI::dbGetQuery(con,"SELECT table_name FROM information_schema.tables WHERE table_schema='main' AND table_type='BASE TABLE' ORDER BY table_name")$table_name
  signatures<-do.call(rbind,lapply(tables,function(t){z<-DBI::dbGetQuery(con,paste0('SELECT count(*) n,CAST(bit_xor(hash(x)) AS VARCHAR) checksum FROM ',DBI::dbQuoteIdentifier(con,t),' x'));data.frame(table=t,z)}))
  utils::write.csv(signatures,file.path(folder,'baseline_tables.csv'),row.names=FALSE)
  saveRDS(DBI::dbReadTable(con,'datasets'),file.path(folder,'baseline_inputs.rds'))
  # Diagnostic identity rules retain every original game/count/minute gate.
  season<-'2023-24';team<-utils::read.csv('config/team_crosswalk.csv',colClasses='character')
  nba<-DBI::dbGetQuery(con,"SELECT l.espn_game_id game_id,p.game_id nba_game_id,p.* EXCLUDE(game_id),n.name FROM historical_player_boxes p JOIN historical_game_links l ON p.game_id=l.nba_game_id JOIN historical_players n USING(player_id) WHERE p.season=? AND p.validation_status='observed'",params=list(season))
  nba$canonical_team<-paste0('espn:',team$espn_id[match(sub('nba:','',nba$team_id),team$nba_id)])
  espn<-DBI::dbGetQuery(con,'SELECT p.*,n.name FROM player_box_scores p JOIN games g USING(game_id) JOIN players n USING(player_id) WHERE g.season=?',params=list(season))
  names_key<-function(x)gsub('[[:punct:][:space:]]','',normalize_name(x))
  rows<-lapply(list(original=normalize_name,trimmed=function(x)normalize_name(trimws(x)),punctuation_space=names_key),function(fun){
    a<-paste(nba$game_id,nba$canonical_team,fun(nba$name));b<-paste(espn$game_id,espn$team_id,fun(espn$name));j<-match(a,b)
    unique<-!is.na(j)&!duplicated(a)&!duplicated(a,fromLast=TRUE)&!duplicated(b)[j]&!duplicated(b,fromLast=TRUE)[j]
    valid<-unique
    for(m in c('fgm','fga','fg3m','fg3a','ftm','fta','points','assists','turnovers','rebounds'))valid<-valid & !is.na(nba[[m]]) & nba[[paste0(m,'_status')]]=='observed' & !is.na(espn[[m]][j]) & nba[[m]]==espn[[m]][j]
    known<-!is.na(nba$minutes)&!is.na(espn$minutes[j]);tol<-ifelse(abs(nba$minutes-round(nba$minutes))<1e-8|abs(espn$minutes[j]-round(espn$minutes[j]))<1e-8,1,1.01/60)
    valid<-valid & (!known|abs(nba$minutes-espn$minutes[j])<=tol);valid[is.na(valid)]<-FALSE
    data.frame(unique_name_pairs=sum(unique,na.rm=TRUE),fully_qualified_pairs=sum(valid),players=length(unique(nba$player_id[valid])),fgas=sum(nba$fga[valid]))
  })
  keys<-names(rows);r<-do.call(rbind,rows);r$rule<-keys;utils::write.csv(r,file.path(out,'identity_pilot.csv'),row.names=FALSE);print(r)
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
