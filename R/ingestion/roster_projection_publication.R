publish_verified_roster_projection <- function(con,path) {
  projection<-readRDS(path);stopifnot(projection$method==roster_projection_method(),file_sha256(projection$source$path)==projection$source$sha256)
  id<-paste0('verified-roster-projection:',projection$method);sha<-file_sha256(path)
  prior<-DBI::dbGetQuery(con,'SELECT sha256 FROM datasets WHERE dataset_id=?',params=list(id))
  if(nrow(prior)) {stopifnot(prior$sha256==sha);return(invisible(0L))}
  DBI::dbWriteTable(con,'_roster_projected_rows',projection$rows,temporary=TRUE,overwrite=TRUE)
  DBI::dbExecute(con,'CREATE TABLE IF NOT EXISTS phase4_verified_player_boxes AS SELECT * FROM historical_player_boxes WHERE FALSE')
  e<-projection$evidence;e$snapshot_id<-projection$source$snapshot_id;e$artifact_dataset_id<-id;e$raw_source_sha256<-projection$source$sha256
  if(!DBI::dbExistsTable(con,'phase4_roster_team_evidence'))DBI::dbWriteTable(con,'phase4_roster_team_evidence',e[FALSE,])
  stopifnot(DBI::dbGetQuery(con,"SELECT count(*) n FROM _roster_projected_rows r LEFT JOIN historical_player_boxes p USING(snapshot_id,source_row) WHERE p.source_row IS NULL OR p.game_id IS DISTINCT FROM r.game_id OR p.player_id IS DISTINCT FROM r.player_id OR p.validation_status='observed' OR p.team_id IS NOT NULL")$n==0)
  DBI::dbWithTransaction(con,{
    upsert_rows(con,'phase4_verified_player_boxes',projection$rows,c('snapshot_id','source_row'))
    upsert_rows(con,'phase4_roster_team_evidence',e,c('snapshot_id','source_row'))
    upsert_rows(con,'datasets',data.frame(dataset_id=id,source_id=projection$source$source_id,url=projection$source$url,revision=projection$method,retrieved_at=Sys.time(),sha256=sha,raw_path=path,row_count=nrow(projection$rows)),'dataset_id')
    parents<-unique(c(DBI::dbGetQuery(con,"SELECT snapshot_id FROM historical_snapshots WHERE kind IN ('games','team','player','players')")$snapshot_id,DBI::dbGetQuery(con,'SELECT DISTINCT p.dataset_id FROM player_box_scores p JOIN phase4_roster_team_evidence e USING(game_id,player_id)')$dataset_id,DBI::dbGetQuery(con,'SELECT DISTINCT g.dataset_id FROM games g JOIN phase4_roster_team_evidence e USING(game_id)')$dataset_id))
    upsert_rows(con,'dataset_dependencies',data.frame(dataset_id=id,parent_dataset_id=parents,transformation='Missing NBA team FK reconstructed only from recorded home side, unique reviewed game link, globally unique validated player IDs, canonical roster and all ten raw counts/minutes; original box gates rerun'),c('dataset_id','parent_dataset_id'))
    checks<-roster_projection_integrity(con);if(any(!checks$passed))stop('Verified roster projection integrity failed')
  })
  invisible(nrow(projection$rows))
}

roster_projection_integrity <- function(con) {
  sql<-c(
    roster_source_pointer="SELECT count(*) FROM phase4_roster_team_evidence e LEFT JOIN historical_player_boxes p USING(snapshot_id,source_row) WHERE p.game_id IS DISTINCT FROM e.nba_game_id OR p.player_id IS DISTINCT FROM e.nba_player_id OR p.team_id IS NOT NULL OR p.validation_status='observed'",
    roster_observed_side="SELECT count(*) FROM phase4_roster_team_evidence e JOIN historical_games g ON e.nba_game_id=g.game_id WHERE e.raw_home NOT IN ('0','1') OR e.nba_team_id IS DISTINCT FROM CASE WHEN e.raw_home='1' THEN g.home_team_id ELSE g.away_team_id END",
    roster_canonical_membership='SELECT count(*) FROM phase4_roster_team_evidence e LEFT JOIN player_box_scores p USING(game_id,player_id) WHERE p.team_id IS DISTINCT FROM e.team_id OR p.did_not_play IS TRUE OR p.minutes IS NULL OR abs(e.minutes-p.minutes)>e.minute_tolerance',
    roster_verified_player_id='SELECT count(*) FROM phase4_roster_team_evidence e WHERE NOT EXISTS(SELECT 1 FROM sdv_nba_player_links l WHERE l.nba_player_id=e.nba_player_id AND l.player_id=e.player_id)',
    roster_box_projection_valid="SELECT count(*) FROM phase4_verified_player_boxes p LEFT JOIN phase4_roster_team_evidence e USING(snapshot_id,source_row) WHERE e.source_row IS NULL OR p.team_id IS DISTINCT FROM e.nba_team_id OR p.validation_status!='observed'",
    roster_artifact_registered='SELECT count(*) FROM phase4_roster_team_evidence e LEFT JOIN datasets d ON e.artifact_dataset_id=d.dataset_id WHERE d.dataset_id IS NULL',
    roster_duplicate_identity='SELECT count(*) FROM (SELECT game_id,player_id FROM phase4_verified_player_boxes GROUP BY ALL HAVING count(*)!=1)')
  for(m in c('fgm','fga','fg3m','fg3a','ftm','fta','points','assists','turnovers','rebounds'))sql[paste0('roster_count_',m)]<-paste0('SELECT count(*) FROM phase4_roster_team_evidence e LEFT JOIN player_box_scores p USING(game_id,player_id) WHERE e.',m,' IS DISTINCT FROM p.',m)
  out<-data.frame(check=names(sql),violations=vapply(sql,function(q)as.numeric(DBI::dbGetQuery(con,q)[[1]][1]),numeric(1)));out$passed<-out$violations==0;out
}
