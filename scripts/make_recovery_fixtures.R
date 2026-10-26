source('scripts/load.R');con<-phase3_snapshot_connection()
tryCatch({
  ids<-c('220215013','400974774')
  cases<-lapply(ids,function(id){
    g<-DBI::dbGetQuery(con,'SELECT * FROM games WHERE game_id=?',params=list(id));e<-DBI::dbGetQuery(con,'SELECT * FROM pbp_events WHERE game_id=? ORDER BY event_order',params=list(id));p<-DBI::dbGetQuery(con,'SELECT p.*,n.name FROM player_box_scores p JOIN players n USING(player_id) WHERE game_id=? ORDER BY player_id',params=list(id));t<-DBI::dbGetQuery(con,'SELECT * FROM team_box_scores WHERE game_id=? ORDER BY team_id',params=list(id))
    datasets<-DBI::dbGetQuery(con,'SELECT d.* FROM datasets d WHERE dataset_id IN (SELECT dataset_id FROM pbp_events WHERE game_id=? UNION SELECT dataset_id FROM player_box_scores WHERE game_id=? UNION SELECT dataset_id FROM team_box_scores WHERE game_id=?)',params=list(id,id,id))
    list(g=g,e=e,p=p,t=t,manifests=datasets,sources=DBI::dbReadTable(con,'sources'))
  });names(cases)<-ids
  saveRDS(cases,'data/sample/phase3_recovery_cases.rds',version=3)
  cat(file_sha256('data/sample/phase3_recovery_cases.rds'),'\n')
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
