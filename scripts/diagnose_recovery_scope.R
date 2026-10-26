source('scripts/load.R');con<-phase3_snapshot_connection()
tryCatch({
  DBI::dbExecute(con,'SET threads=2')
  ft<-DBI::dbGetQuery(con,"WITH f AS (SELECT game_id,period,clock,team_id,player_id,event_order,CAST(regexp_extract(lower(event_type),'([123]) of [123]',1) AS INTEGER) ordinal,CAST(regexp_extract(lower(event_type),'[123] of ([123])',1) AS INTEGER) n FROM pbp_events WHERE regexp_matches(lower(event_type),'free throw.*[123] of [123]') AND NOT regexp_matches(lower(event_type),'technical|flagrant|clear path|away from')), t AS (SELECT *,lag(ordinal) OVER(PARTITION BY game_id,period,clock,team_id,player_id ORDER BY event_order) prior_ordinal FROM f) SELECT DISTINCT game_id FROM t WHERE ordinal<prior_ordinal")$game_id
  lu<-DBI::dbGetQuery(con,'SELECT DISTINCT game_id FROM (SELECT game_id,team_id FROM player_box_scores WHERE did_not_play IS DISTINCT FROM TRUE GROUP BY game_id,team_id HAVING bool_and(starter IS NULL))')$game_id
  scope<-DBI::dbGetQuery(con,'SELECT g.game_id,g.season,r.possessions_status,r.lineups_status FROM games g JOIN reconstruction_status r USING(game_id) ORDER BY g.season,g.game_id')
  scope$free_throw_pattern<-scope$game_id%in%ft;scope$missing_starters<-scope$game_id%in%lu
  scope<-scope[scope$free_throw_pattern|scope$missing_starters,]
  utils::write.csv(scope,'data/processed/phase3/recovery_scope.csv',row.names=FALSE)
  print(aggregate(rep(1,nrow(scope)),scope[c('season','free_throw_pattern','missing_starters')],sum))
  pilot<-readRDS('data/processed/phase3/possession_pilot_inputs.rds')
  result<-lapply(pilot,function(x){a<-recovery_projection(x$e,x$p);before<-reconstruct_possessions(x$e,x$g,x$p);after<-reconstruct_possessions(a$e,x$g,a$p);list(game_id=x$g$game_id,audit=a$audit,before=before$issues,after=after$issues)})
  saveRDS(result,'data/processed/phase3/recovery_pilot.rds');print(result[vapply(result,function(x)nrow(x$audit)>0,logical(1))])
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
