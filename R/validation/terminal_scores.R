# Explicit observed terminal markers, not numeric event-ID or physical-row order.
# Legacy NBA check rows are preserved; this is an additional evidence path.
terminal_score_evidence <- function(con,season=NULL) {
  where<-if(is.null(season))'' else paste0(' WHERE season=',DBI::dbQuoteString(con,season))
  sql<-paste0("WITH periods AS (SELECT game_id,max(period) final_period FROM historical_events",where," GROUP BY game_id), ends AS (SELECT e.*,p.final_period FROM historical_events e JOIN periods p USING(game_id) WHERE lower(trim(e.event_type))='game' AND lower(trim(e.description))='game end'",if(is.null(season))'' else paste0(' AND e.season=',DBI::dbQuoteString(con,season)),"), grouped AS (SELECT game_id,min(season) season,count(*) markers,count(DISTINCT row(home_score,away_score)) score_pairs,bool_and(home_score IS NOT NULL AND away_score IS NOT NULL AND home_score>=0 AND away_score>=0 AND period=final_period AND period>=4 AND regexp_full_match(clock,'(PT00M00([.]0+)?S|0:00|00:00)')) valid_terminal,min(snapshot_id) snapshot_id,min(source_row) source_row,min(event_id) event_id,min(period) period,min(home_score) home_score,min(away_score) away_score FROM ends GROUP BY game_id) SELECT z.*,g.home_team_id,g.away_team_id,g.home_score game_home_score,g.away_score game_away_score FROM grouped z JOIN historical_games g USING(game_id)")
  out<-DBI::dbGetQuery(con,sql)
  if(!nrow(out)) {out$eligible<-logical();return(out)}
  # Reject competing terminal pairs before looking at any expected score.
  out$eligible<-out$valid_terminal%in%TRUE & out$score_pairs==1L & out$home_score==out$game_home_score & out$away_score==out$game_away_score
  boxes<-DBI::dbGetQuery(con,paste0('SELECT game_id,team_id,points,points_status,validation_status FROM historical_team_boxes',where))
  for(home in c(TRUE,FALSE)) {
    team<-if(home)out$home_team_id else out$away_team_id;score<-if(home)out$home_score else out$away_score
    key<-paste(boxes$game_id,boxes$team_id);j<-match(paste(out$game_id,team),key)
    out$eligible<-out$eligible & !is.na(j) & !duplicated(key)[j] & !duplicated(key,fromLast=TRUE)[j] & boxes$points_status[j]=='observed' & boxes$validation_status[j]=='observed' & score==boxes$points[j]
  }
  out$eligible[is.na(out$eligible)]<-FALSE
  out
}
