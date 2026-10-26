source('scripts/load.R');con<-phase3_snapshot_connection()
tryCatch({
  q<-DBI::dbGetQuery(con,"SELECT DISTINCT a.game_id FROM pbp_events a JOIN pbp_events b ON a.game_id=b.game_id AND a.period=b.period AND a.clock=b.clock AND a.team_id=b.team_id AND a.player_id=b.secondary_player_id WHERE lower(a.event_type) LIKE '%substitution%' AND lower(b.event_type) LIKE '%substitution%' AND a.event_order>b.event_order")
  scope<-DBI::dbGetQuery(con,'SELECT g.game_id,g.season,r.possessions_status,r.lineups_status FROM games g JOIN reconstruction_status r USING(game_id) ORDER BY g.season,g.game_id')
  scope<-scope[scope$game_id%in%q$game_id,];utils::write.csv(scope,'data/processed/phase3/substitution_scope.csv',row.names=FALSE);print(table(scope$season,scope$lineups_status))
  xs<-readRDS('data/processed/phase3/lineup_pilot_inputs.rds')
  for(x in xs) {
    issue<-x$lu$issues[grepl('unresolvable substitution',x$lu$issues)][1];if(is.na(issue))next
    id<-sub('.*substitution ','',issue);j<-match(id,x$e$event_id);cat('\n',x$g$game_id,issue,'\n');print(x$e[seq(max(1,j-2),min(nrow(x$e),j+2)),c('event_id','period','clock','event_type','description','player_id','secondary_player_id')])
  }
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
