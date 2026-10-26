source('scripts/load.R');con<-DBI::dbConnect(duckdb::duckdb(),dbdir='data/processed/phase4/baseline.duckdb',read_only=TRUE)
tryCatch({
  team<-utils::read.csv('config/team_crosswalk.csv',colClasses='character');season<-'2021-22'
  print(DBI::dbGetQuery(con,"SELECT season,validation_status,count(*) n,count(DISTINCT game_id) games FROM historical_player_boxes WHERE season IN ('2020-21','2021-22','2022-23') GROUP BY ALL"))
  print(DBI::dbGetQuery(con,"SELECT p.season,count(*) joined_rows,count(DISTINCT p.game_id) nba_games,count(DISTINCT l.espn_game_id) espn_games FROM historical_player_boxes p JOIN historical_game_links l ON p.game_id=l.nba_game_id WHERE p.season IN ('2020-21','2021-22','2022-23') GROUP BY p.season"))
  print(DBI::dbGetQuery(con,"SELECT p.game_id,p.player_id,p.team_id,p.identity_evidence,p.points,p.fgm,p.fg3m,p.ftm,p.points_status,p.fgm_status FROM historical_player_boxes p WHERE p.season='2021-22' AND p.validation_status='failed_validation' LIMIT 6"))
  nba<-DBI::dbGetQuery(con,"SELECT l.espn_game_id game_id,p.game_id nba_game_id,p.* EXCLUDE(game_id),n.name FROM historical_player_boxes p JOIN historical_game_links l ON p.game_id=l.nba_game_id JOIN historical_players n USING(player_id) WHERE p.season=? AND p.validation_status='observed'",params=list(season))
  nba$canonical_team<-paste0('espn:',team$espn_id[match(sub('nba:','',nba$team_id),team$nba_id)])
  espn<-DBI::dbGetQuery(con,'SELECT p.*,n.name FROM player_box_scores p JOIN games g USING(game_id) JOIN players n USING(player_id) WHERE g.season=?',params=list(season))
  a<-paste(nba$game_id,nba$canonical_team,normalize_name(nba$name));b<-paste(espn$game_id,espn$team_id,normalize_name(espn$name));j<-match(a,b);ok<-!is.na(j)&!duplicated(a)&!duplicated(a,fromLast=TRUE)&!duplicated(b)[j]&!duplicated(b,fromLast=TRUE)[j];ok[is.na(ok)]<-FALSE
  out<-lapply(c('fgm','fga','fg3m','fg3a','ftm','fta','points','assists','turnovers','rebounds','minutes'),function(m)data.frame(metric=m,matched_name_rows=sum(ok),known_nba=sum(ok&!is.na(nba[[m]])),known_espn=sum(ok&!is.na(espn[[m]][j])),equal=sum(ok&nba[[m]]==espn[[m]][j],na.rm=TRUE)))
  utils::write.csv(do.call(rbind,out),'docs/phase4/identity_gate_failures_2022.csv',row.names=FALSE);print(do.call(rbind,out))
  i<-which(ok & nba$fga>5)[1:3];print(nba[i,c('game_id','name','fgm','fga','fg3m','fg3a','ftm','fta','points','assists','turnovers','rebounds','minutes')]);print(espn[j[i],c('game_id','name','fgm','fga','fg3m','fg3a','ftm','fta','points','assists','turnovers','rebounds','minutes')])
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
