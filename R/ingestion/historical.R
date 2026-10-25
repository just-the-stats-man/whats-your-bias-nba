historical_checkpoint <- function(con,snapshot_id,season,transform_id) {
  upsert_rows(con,'historical_checkpoints',data.frame(snapshot_id=snapshot_id,season=season,transform_id=transform_id,completed_at=Sys.time()),c('snapshot_id','season'))
}

historical_check_boxes <- function(con,season) {
  q<-DBI::dbQuoteString(con,season)
  DBI::dbExecute(con,paste0('DELETE FROM historical_box_checks WHERE season=',q))
  for(m in setdiff(historical_metrics()$metric,'minutes')) {
    DBI::dbExecute(con,paste0("INSERT INTO historical_box_checks WITH p AS (SELECT game_id,team_id,count(*) n,count(DISTINCT player_id) unique_players,count(*) FILTER (WHERE ",m,"_status!='observed' OR validation_status='failed_validation') unknown_count,sum(",m,") measured_sum FROM historical_player_boxes WHERE season=",q," GROUP BY game_id,team_id) SELECT t.game_id,t.team_id,t.season,'",m,"',p.measured_sum,t.",m,",CASE WHEN t.validation_status='failed_validation' THEN 'failed_validation' WHEN t.",m,"_status IN ('not_applicable','not_collected') THEN t.",m,"_status WHEN t.",m,"_status!='observed' OR p.n IS NULL OR p.unknown_count>0 OR p.n!=p.unique_players THEN 'source_missing' WHEN p.measured_sum!=t.",m," THEN 'failed_validation' ELSE 'reconstructed' END FROM historical_team_boxes t LEFT JOIN p USING(game_id,team_id) WHERE t.season=",q))
  }
}

ingest_historical_boxes <- function(con,items=NULL,seasons=NULL) {
  historical_schema(con)
  if(is.null(items))items<-setNames(lapply(c('games','team','player'),historical_file),c('games','team','player'))
  for(k in names(items))items[[k]]<-historical_raw(con,items[[k]])
  existing<-DBI::dbGetQuery(con,'SELECT DISTINCT snapshot_id FROM historical_games')$snapshot_id
  if(length(existing) && !identical(existing,items$games$snapshot_id))stop('Different game snapshot: preserve current observations and review revision migration')
  if(!length(existing))DBI::dbWithTransaction(con,historical_prepare_games(con,items$games))
  available<-DBI::dbGetQuery(con,'SELECT DISTINCT season FROM historical_games ORDER BY season')$season
  if(is.null(seasons))seasons<-available
  if(any(!seasons%in%available))stop('Selected season absent from historical game index')
  transform<-historical_transform_id()
  for(season in seasons) {
    done<-DBI::dbGetQuery(con,'SELECT snapshot_id,transform_id FROM historical_checkpoints WHERE season=?',params=list(season))
    ids<-vapply(items[c('team','player')],`[[`,character(1),'snapshot_id')
    if(all(ids%in%done$snapshot_id[done$transform_id==transform]))next
    DBI::dbWithTransaction(con,{
      for(kind in c('team','player')) {
        id<-items[[kind]]$snapshot_id
        DBI::dbExecute(con,paste0('DELETE FROM historical_',kind,'_boxes WHERE season=?'),params=list(season))
        sql<-historical_box_sql(con,kind,id,season)
        DBI::dbExecute(con,paste0('INSERT INTO historical_',kind,'_boxes ',sql))
        DBI::dbExecute(con,'DELETE FROM historical_exceptions WHERE family=? AND season=?',params=list(kind,season))
        DBI::dbExecute(con,paste0("INSERT INTO historical_exceptions SELECT snapshot_id,source_row,'",kind,"',game_id,season,'box scoring identity, duplicate or entity assignment failed' FROM historical_",kind,"_boxes WHERE season=? AND validation_status='failed_validation'"),params=list(season))
        historical_checkpoint(con,id,season,transform)
      }
      historical_check_boxes(con,season)
    })
    message(season,': historical boxes committed')
  }
  # Unmatched rows remain raw and receive pointers, including excluded competitions.
  for(kind in c('team','player')) {
    id<-items[[kind]]$snapshot_id
    DBI::dbExecute(con,"DELETE FROM historical_exceptions WHERE snapshot_id=? AND rule='raw row outside admitted historical boxes'",params=list(id))
    DBI::dbExecute(con,paste0("INSERT INTO historical_exceptions SELECT ",DBI::dbQuoteString(con,id),",r.source_row,'",kind,"','nba:'||",historical_sql_id('r.gameId'),",NULL,'raw row outside admitted historical boxes' FROM _history_",kind," r LEFT JOIN historical_",kind,"_boxes b ON r.source_row=b.source_row AND b.snapshot_id=",DBI::dbQuoteString(con,id)," WHERE b.source_row IS NULL"))
  }
  invisible(items)
}

ingest_historical_events <- function(con,item=historical_file('pbp'),seasons=NULL) {
  historical_schema(con)
  item$snapshot_id<-paste0('nba-history:pbp:',item$sha256)
  # Use a lazy view over the immutable Parquet, avoiding a 19-million-row copy.
  prior<-DBI::dbGetQuery(con,'SELECT sha256 FROM historical_snapshots WHERE path=?',params=list(item$path))$sha256
  if(length(prior) && any(prior!=item$sha256))stop('Raw path changed since registration: ',item$path)
  DBI::dbExecute(con,sprintf('CREATE OR REPLACE TEMP VIEW _history_pbp AS SELECT file_row_number+1 source_row,* EXCLUDE(file_row_number) FROM read_parquet(%s,file_row_number=TRUE)',DBI::dbQuoteString(con,normalizePath(item$path,winslash='/'))))
  n<-as.numeric(DBI::dbGetQuery(con,'SELECT count(*) n FROM _history_pbp')$n)
  upsert_rows(con,'historical_snapshots',data.frame(snapshot_id=item$snapshot_id,source_id='eoin_moore_nba',upstream='NBA.com',revision=item$revision,kind='pbp',path=item$path,url=item$url,sha256=item$sha256,raw_rows=n),'snapshot_id')
  available<-DBI::dbGetQuery(con,paste0("SELECT DISTINCT g.season FROM _history_pbp r JOIN historical_games g ON 'nba:'||",historical_sql_id('r.gameId'),"=g.game_id ORDER BY g.season"))$season
  if(is.null(seasons))seasons<-available
  if(any(!seasons%in%available))stop('Selected event season absent from raw archive')
  transform<-historical_transform_id();q<-function(x)as.character(DBI::dbQuoteString(con,x))
  for(season in seasons) {
    done<-DBI::dbGetQuery(con,'SELECT * FROM historical_checkpoints WHERE snapshot_id=? AND season=? AND transform_id=?',params=list(item$snapshot_id,season,transform))
    if(nrow(done))next
    # Freeze physical raw row ordinals before filtering. Source action numbers
    # are retained separately and can repeat; neither is assumed to be ESPN's ID.
    DBI::dbExecute(con,paste0("CREATE OR REPLACE TEMP TABLE _history_event_season AS SELECT r.*,g.game_id,g.season FROM _history_pbp r JOIN historical_games g ON 'nba:'||",historical_sql_id('r.gameId'),"=g.game_id WHERE g.season=",q(season)))
    DBI::dbWithTransaction(con,{
      for(t in c('historical_events','historical_shots'))DBI::dbExecute(con,paste('DELETE FROM',t,'WHERE season=?'),params=list(season))
      DBI::dbExecute(con,paste0("INSERT INTO historical_events SELECT ",q(item$snapshot_id),",source_row,game_id,season,CAST(actionNumber AS VARCHAR),period,coalesce(clock,shortFormattedClock),actionType,description,CASE WHEN TRY_CAST(teamId AS BIGINT)>0 THEN 'nba:'||teamId END,CASE WHEN TRY_CAST(personId AS BIGINT)>0 THEN 'nba:'||personId END,scoreHome,scoreAway FROM _history_event_season"))
      DBI::dbExecute(con,paste0("INSERT INTO historical_shots SELECT ",q(item$snapshot_id),",source_row,game_id,season,CASE WHEN TRY_CAST(personId AS BIGINT)>0 THEN 'nba:'||personId END,CASE WHEN TRY_CAST(teamId AS BIGINT)>0 THEN 'nba:'||teamId END,CASE WHEN actionType='Made Shot' OR shotResult='Made' THEN TRUE WHEN actionType='Missed Shot' OR shotResult='Missed' THEN FALSE END,CASE WHEN actionType='2pt' THEN 2 WHEN actionType='3pt' THEN 3 WHEN shotValue IN (2,3) THEN shotValue END,CASE WHEN actionType IN ('2pt','3pt') OR shotValue IN (2,3) THEN 'observed' ELSE 'source_missing' END,x,y,xLegacy,yLegacy,CASE WHEN actionType IN ('2pt','3pt') THEN 'nba_live_raw' ELSE 'nba_legacy_raw' END,CASE WHEN actionType IN ('2pt','3pt') AND x BETWEEN 0 AND 100 AND y BETWEEN 0 AND 100 THEN 'observed' WHEN actionType IN ('Made Shot','Missed Shot') AND xLegacy BETWEEN -250 AND 250 AND yLegacy BETWEEN -100 AND 1000 AND (xLegacy!=0 OR yLegacy!=0) THEN 'observed' ELSE 'source_missing' END,CASE WHEN shotDistance>=0 AND NOT ((actionType='3pt' OR coalesce(shotValue=3,FALSE)) AND shotDistance=0) THEN shotDistance END,CASE WHEN shotDistance>=0 AND NOT ((actionType='3pt' OR coalesce(shotValue=3,FALSE)) AND shotDistance=0) THEN 'observed' ELSE 'source_missing' END FROM _history_event_season WHERE actionType IN ('Made Shot','Missed Shot','2pt','3pt')"))
      historical_checkpoint(con,item$snapshot_id,season,transform)
    })
    message(season,': historical events and shots committed')
  }
  invisible(item)
}
