source('scripts/load.R');con<-phase3_snapshot_connection()
tryCatch({
  q<-utils::read.csv('data/processed/phase3/count_qualified_unresolved.csv',colClasses=c(game_id='character'))
  q<-q[q$lineups_status!='reconciled',];ids<-unlist(lapply(split(q$game_id,q$season),head,5),use.names=FALSE)
  result<-lapply(ids,function(id){
    g<-DBI::dbGetQuery(con,'SELECT * FROM games WHERE game_id=?',params=list(id));e<-DBI::dbGetQuery(con,'SELECT * FROM pbp_events WHERE game_id=? ORDER BY event_order',params=list(id));p<-DBI::dbGetQuery(con,'SELECT * FROM player_box_scores WHERE game_id=?',params=list(id));lu<-reconstruct_lineups(e,g,p)
    list(g=g,e=e,p=p,lu=lu)
  })
  saveRDS(result,'data/processed/phase3/lineup_pilot_inputs.rds')
  for(x in result){cat(x$g$season,x$g$game_id,'\n');print(x$lu$issues);print(head(x$lu$checks[!x$lu$checks$passed,],3))}
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
