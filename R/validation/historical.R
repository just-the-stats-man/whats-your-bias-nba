historical_integrity <- function(con) {
  queries<-c(
    historical_boxes_without_game="SELECT count(*) FROM (SELECT game_id FROM historical_team_boxes UNION ALL SELECT game_id FROM historical_player_boxes) b LEFT JOIN historical_games g USING(game_id) WHERE g.game_id IS NULL",
    historical_events_without_game='SELECT count(*) FROM historical_events e LEFT JOIN historical_games g USING(game_id) WHERE g.game_id IS NULL',
    historical_shots_without_event='SELECT count(*) FROM historical_shots s LEFT JOIN historical_events e USING(snapshot_id,source_row) WHERE e.source_row IS NULL',
    historical_game_season_century="SELECT count(*) FROM historical_games WHERE CAST(substr(season,1,4) AS INTEGER)!=start_year OR start_year%100!=CAST(substr(source_game_id,4,2) AS INTEGER) OR year(game_date)-start_year NOT IN (0,1)",
    historical_unexplained_event_pointer='SELECT count(*) FROM historical_events WHERE source_row<1 OR game_id IS NULL',
    historical_shot_value_status="SELECT count(*) FROM historical_shots WHERE (points_status='observed' AND points_attempted NOT IN (2,3)) OR (points_status!='observed' AND points_attempted IS NOT NULL)",
    historical_game_snapshot_missing='SELECT count(*) FROM historical_games g LEFT JOIN historical_snapshots s USING(snapshot_id) WHERE s.snapshot_id IS NULL',
    historical_tied_final_scores='SELECT count(*) FROM historical_games WHERE home_score=away_score',
    historical_distance_status="SELECT count(*) FROM historical_shots WHERE distance_status IS NULL OR (distance_status='observed' AND distance IS NULL) OR (distance_status!='observed' AND distance IS NOT NULL)",
    historical_box_snapshot_missing='SELECT count(*) FROM (SELECT snapshot_id FROM historical_team_boxes UNION SELECT snapshot_id FROM historical_player_boxes) b LEFT JOIN historical_snapshots s USING(snapshot_id) WHERE s.snapshot_id IS NULL')
  for(kind in c('team','player'))for(m in historical_metrics()$metric) {
    queries[paste('historical',kind,m,'null_semantics',sep='_')]<-paste0("SELECT count(*) FROM historical_",kind,"_boxes WHERE (",m,"_status='observed' AND \"",m,"\" IS NULL) OR (",m,"_status!='observed' AND \"",m,"\" IS NOT NULL)")
  }
  result<-data.frame(check=names(queries),violations=vapply(queries,function(q)as.numeric(DBI::dbGetQuery(con,q)[[1]][1]),numeric(1)))
  result$passed<-result$violations==0
  result
}

historical_game_links <- function(con) {
  map<-utils::read.csv('config/team_crosswalk.csv',colClasses='character')
  # The present franchise crosswalk cannot establish the old Charlotte/New
  # Orleans reassignment. Explicitly leave that edge unmapped before 2002.
  values<-paste(sprintf("('espn:%s','nba:%s')",map$espn_id,map$nba_id),collapse=',')
  DBI::dbExecute(con,paste0("CREATE OR REPLACE VIEW historical_game_links AS WITH m(espn_id,nba_id) AS (VALUES ",values,") SELECT i.game_id espn_game_id,g.game_id nba_game_id,g.season,'unique season/date and reviewed franchise-ID pair; no player-name matching' evidence FROM schedule_inventory i JOIN m h ON i.home_team_id=h.espn_id JOIN m a ON i.away_team_id=a.espn_id JOIN historical_games g ON i.season=g.season AND i.game_date=g.game_date AND h.nba_id=g.home_team_id AND a.nba_id=g.away_team_id WHERE (g.start_year>=2002 OR (i.home_team_id!='espn:3' AND i.away_team_id!='espn:3')) AND (g.start_year>=2004 OR (i.home_team_id!='espn:30' AND i.away_team_id!='espn:30')) QUALIFY count(*) OVER(PARTITION BY i.game_id)=1 AND count(*) OVER(PARTITION BY g.game_id)=1"))
}

historical_overlap_checks <- function(con) {
  historical_game_links(con)
  DBI::dbExecute(con,'CREATE OR REPLACE TABLE historical_overlap_checks (espn_game_id VARCHAR,nba_game_id VARCHAR,season VARCHAR,team_id VARCHAR,metric VARCHAR,warehouse_value DOUBLE,reference_value DOUBLE,status VARCHAR)')
  map<-utils::read.csv('config/team_crosswalk.csv',colClasses='character')
  DBI::dbWriteTable(con,'_historical_team_map',data.frame(team_id=paste0('espn:',map$espn_id),nba_team=paste0('nba:',map$nba_id)),temporary=TRUE,overwrite=TRUE)
  for(m in c('points','fgm','fga','fg3m','fg3a','ftm','fta','assists','turnovers')) {
    ref<-if(m=='turnovers')"CASE WHEN p.unknown_count=0 AND p.n=p.unique_players AND NOT EXISTS (SELECT 1 FROM historical_player_boxes b WHERE b.game_id=t.game_id AND (b.team_id IS NULL OR b.validation_status='failed_validation')) THEN p.measured_sum END" else paste0("CASE WHEN t.",m,"_status='observed' THEN t.",m,' END')
    DBI::dbExecute(con,paste0("INSERT INTO historical_overlap_checks WITH p AS (SELECT game_id,team_id,count(*) n,count(DISTINCT player_id) unique_players,count(*) FILTER (WHERE turnovers_status!='observed') unknown_count,sum(turnovers) measured_sum FROM historical_player_boxes GROUP BY game_id,team_id), b AS (SELECT l.espn_game_id,l.nba_game_id,l.season,w.team_id,'",m,"' metric,w.",m," warehouse_value,",ref," reference_value FROM historical_game_links l JOIN team_box_scores w ON w.game_id=l.espn_game_id JOIN _historical_team_map m ON w.team_id=m.team_id JOIN historical_team_boxes t ON t.game_id=l.nba_game_id AND t.team_id=m.nba_team LEFT JOIN p ON p.game_id=t.game_id AND p.team_id=t.team_id WHERE t.validation_status='observed') SELECT *,CASE WHEN warehouse_value IS NULL OR reference_value IS NULL THEN 'source_missing' WHEN warehouse_value=reference_value THEN 'reconstructed' ELSE 'failed_validation' END FROM b"))
  }
  invisible(NULL)
}

historical_season_views <- function(con) {
  for(kind in c('team','player')) {
    entity<-if(kind=='team')'team_id' else 'player_id,team_id'
    metrics<-unlist(lapply(historical_metrics()$metric,function(m)c(paste0('sum("',m,'") ',m,'_covered_total'),paste0("count(*) FILTER (WHERE ",m,"_status='observed') ",m,'_recorded_rows'))))
    DBI::dbExecute(con,paste0("CREATE OR REPLACE VIEW historical_",kind,"_season_totals AS SELECT b.season,g.competition,",paste0('b.',strsplit(entity,',')[[1]],collapse=','),",count(*) covered_box_rows,'reconstructed' observation_type,'partial game-log sums; not official full-season totals or standings' coverage_definition,",paste(metrics,collapse=','),' FROM historical_',kind,"_boxes b JOIN historical_games g USING(game_id) WHERE b.validation_status='observed' GROUP BY b.season,g.competition,",paste0('b.',strsplit(entity,',')[[1]],collapse=',')))
  }
}

historical_completeness <- function(con,directory='docs',artifact_directory='data/processed/reports') {
  dir.create(directory,recursive=TRUE,showWarnings=FALSE)
  historical_quarantine_invalid_games(con)
  historical_overlap_checks(con);historical_season_views(con);historical_event_checks(con)
  report<-DBI::dbGetQuery(con,"WITH source_games AS (SELECT season,count(*) source_games FROM historical_games GROUP BY season), team AS (SELECT season,count(DISTINCT game_id) team_box_games,count(*) team_rows,count(*) FILTER (WHERE validation_status='observed') score_identity_valid_team_rows FROM historical_team_boxes GROUP BY season), player AS (SELECT season,count(DISTINCT game_id) player_box_games,count(*) player_rows FROM historical_player_boxes GROUP BY season), checks AS (SELECT season,count(*) FILTER (WHERE checks_passed) player_team_validated_games FROM (SELECT season,game_id,count(*) FILTER (WHERE metric!='turnovers')=28 AND bool_and(metric='turnovers' OR status IN ('reconstructed','not_applicable','not_collected')) checks_passed FROM historical_box_checks GROUP BY season,game_id) GROUP BY season), events AS (SELECT season,count(*) event_rows,count(DISTINCT game_id) pbp_games FROM historical_events GROUP BY season), shots AS (SELECT season,count(*) shot_rows,count(*) FILTER (WHERE coordinate_status='observed') coordinate_rows FROM historical_shots GROUP BY season), canonical AS (SELECT season,count(*) canonical_games FROM games GROUP BY season), possession AS (SELECT g.season,count(*) possession_rows,count(DISTINCT p.game_id) possession_games FROM possessions p JOIN games g USING(game_id) GROUP BY g.season), lineup AS (SELECT g.season,count(*) lineup_rows,count(DISTINCT l.game_id) lineup_games FROM lineups l JOIN games g USING(game_id) GROUP BY g.season), overlapping AS (SELECT season,count(DISTINCT espn_game_id) reference_agree_games FROM (SELECT season,espn_game_id FROM historical_overlap_checks GROUP BY season,espn_game_id HAVING count(*)=18 AND bool_and(status='reconstructed')) GROUP BY season) SELECT source_games.*,CAST(NULL AS BIGINT) expected_games,'not established by an independent complete schedule' denominator_status,coalesce(team_box_games,0) team_box_games,coalesce(team_rows,0) team_rows,coalesce(score_identity_valid_team_rows,0) score_identity_valid_team_rows,coalesce(player_box_games,0) player_box_games,coalesce(player_rows,0) player_rows,coalesce(player_team_validated_games,0) player_team_validated_games,coalesce(pbp_games,0) pbp_games,coalesce(event_rows,0) event_rows,coalesce(shot_rows,0) shot_rows,coalesce(coordinate_rows,0) coordinate_rows,coalesce(canonical_games,0) canonical_games,coalesce(possession_games,0) possession_games,coalesce(possession_rows,0) possession_rows,coalesce(lineup_games,0) lineup_games,coalesce(lineup_rows,0) lineup_rows,coalesce(reference_agree_games,0) box_total_agree_games,0 tracking_observations,'no observed optical tracking in this NBA layer; provider estimates reported separately' tracking_status FROM source_games LEFT JOIN team USING(season) LEFT JOIN player USING(season) LEFT JOIN checks USING(season) LEFT JOIN events USING(season) LEFT JOIN shots USING(season) LEFT JOIN canonical USING(season) LEFT JOIN possession USING(season) LEFT JOIN lineup USING(season) LEFT JOIN overlapping USING(season) ORDER BY season")
  qualified<-DBI::dbGetQuery(con,"SELECT season,count(*) qualified_games FROM (SELECT season,game_id FROM historical_event_checks GROUP BY season,game_id HAVING count(*)=10 AND bool_and(status='reconstructed')) GROUP BY season")
  report$same_upstream_shot_and_score_checked_games<-qualified$qualified_games[match(report$season,qualified$season)]
  report$same_upstream_shot_and_score_checked_games[is.na(report$same_upstream_shot_and_score_checked_games)]<-0
  quarantined<-DBI::dbGetQuery(con,'SELECT season,count(*) games FROM historical_game_quarantine GROUP BY season')
  report$quarantined_source_games<-quarantined$games[match(report$season,quarantined$season)]
  report$quarantined_source_games[is.na(report$quarantined_source_games)]<-0
  utils::write.csv(DBI::dbReadTable(con,'historical_game_quarantine'),file.path(directory,'historical_quarantined_games.csv'),row.names=FALSE)
  utils::write.csv(report,file.path(directory,'historical_completeness.csv'),row.names=FALSE,na='')
  utils::write.csv(historical_family_matrix(con,report),file.path(directory,'historical_availability_matrix.csv'),row.names=FALSE)
  # Detailed artifacts remain local; publish compact summaries, not source feeds.
  local<-artifact_directory;dir.create(local,recursive=TRUE,showWarnings=FALSE)
  for(table in c('historical_exceptions','historical_overlap_checks','historical_box_checks','historical_game_links','historical_event_checks'))DBI::dbExecute(con,sprintf('COPY (SELECT * FROM %s) TO %s (FORMAT PARQUET)',table,DBI::dbQuoteString(con,normalizePath(file.path(local,paste0(table,'.parquet')),mustWork=FALSE))))
  summary<-DBI::dbGetQuery(con,"SELECT season,metric,status,count(*) checks FROM historical_overlap_checks GROUP BY season,metric,status ORDER BY season,metric,status")
  utils::write.csv(summary,file.path(directory,'historical_reconciliation.csv'),row.names=FALSE)
  internal<-DBI::dbGetQuery(con,'SELECT season,metric,status,count(*) checks FROM historical_event_checks GROUP BY season,metric,status ORDER BY season,metric,status')
  utils::write.csv(internal,file.path(directory,'historical_event_consistency.csv'),row.names=FALSE)
  availability<-do.call(rbind,lapply(c('team','player'),function(kind)do.call(rbind,lapply(historical_metrics()$metric,function(m)DBI::dbGetQuery(con,paste0("SELECT season,'",kind,"' AS \"family\",'",m,"' metric,",m,"_status status,count(*) records FROM historical_",kind,"_boxes GROUP BY season,",m,"_status"))))))
  utils::write.csv(availability,file.path(directory,'historical_metric_availability.csv'),row.names=FALSE)
  gaps<-DBI::dbGetQuery(con,"WITH e AS (SELECT game_id,count(*) event_rows FROM historical_events GROUP BY game_id), s AS (SELECT game_id,count(*) shot_rows FROM historical_shots GROUP BY game_id), c AS (SELECT game_id,count(*)=10 AND bool_and(status='reconstructed') shot_score_checks_passed FROM historical_event_checks GROUP BY game_id) SELECT i.season,i.game_id espn_game_id,i.validation_status,i.has_pbp,l.nba_game_id,coalesce(e.event_rows,0) alternative_nba_event_rows,coalesce(s.shot_rows,0) alternative_nba_shot_rows,c.shot_score_checks_passed,'separate NBA namespace; not admitted into strict ESPN reconstruction' disposition FROM schedule_inventory i LEFT JOIN historical_game_links l ON i.game_id=l.espn_game_id LEFT JOIN e ON l.nba_game_id=e.game_id LEFT JOIN s ON l.nba_game_id=s.game_id LEFT JOIN c ON l.nba_game_id=c.game_id WHERE i.season>='2015-16' AND (i.validation_status='quarantined' OR NOT i.has_pbp) ORDER BY i.season,i.game_id")
  utils::write.csv(gaps,file.path(directory,'historical_modern_gap_audit.csv'),row.names=FALSE,na='')
  unresolved<-DBI::dbGetQuery(con,"WITH q AS (SELECT game_id,string_agg(DISTINCT stage||': '||rule,'; ') errors FROM quality_exceptions WHERE version=? AND severity='error' GROUP BY game_id) SELECT i.season,i.game_id,i.validation_status,coalesce(s.possessions_status,'not_reconstructed') possessions_status,coalesce(s.lineups_status,'not_reconstructed') lineups_status,q.errors FROM schedule_inventory i LEFT JOIN reconstruction_status s ON i.game_id=s.game_id LEFT JOIN q ON i.game_id=q.game_id WHERE i.season<'2015-16' AND (i.validation_status='quarantined' OR s.possessions_status IS DISTINCT FROM 'reconciled' OR s.lineups_status IS DISTINCT FROM 'reconciled') ORDER BY i.season,i.game_id",params=list(reconstruction_version))
  utils::write.csv(unresolved,file.path(directory,'historical_unresolved_games.csv'),row.names=FALSE,na='')
  exceptions<-DBI::dbGetQuery(con,'SELECT season,family,rule,count(*) records FROM historical_exceptions GROUP BY season,family,rule ORDER BY season,family,rule')
  utils::write.csv(exceptions,file.path(directory,'historical_exception_summary.csv'),row.names=FALSE,na='')
  integrity<-historical_integrity(con)
  utils::write.csv(integrity,file.path(directory,'historical_integrity.csv'),row.names=FALSE)
  if(any(!integrity$passed))stop('Historical integrity failed; see report')
  report
}
