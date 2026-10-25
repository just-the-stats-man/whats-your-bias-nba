sdv_history_schema <- function(con) {
  DBI::dbExecute(con,"CREATE TABLE IF NOT EXISTS sdv_history_status (game_id VARCHAR PRIMARY KEY,season VARCHAR,signature VARCHAR,box_status VARCHAR,event_status VARCHAR,shot_rows INTEGER,unknown_attempts INTEGER,completed_at TIMESTAMP)")
  DBI::dbExecute(con,"CREATE TABLE IF NOT EXISTS sdv_history_checkpoints (season VARCHAR PRIMARY KEY,signature VARCHAR,completed_at TIMESTAMP)")
}

ingest_sdv_history <- function(con,season,directory='data/processed/sdv_history') {
  sdv_history_schema(con);b<-fetch_sdv_history(season)
  register_sdv_history_raw(con,b,season)
  sig<-substr(digest::digest(list(vapply(b,`[[`,character(1),'sha256'),sdv_history_version()),algo='sha256'),1,24)
  done<-DBI::dbGetQuery(con,'SELECT * FROM sdv_history_checkpoints WHERE season=? AND signature=?',params=list(season,sig))
  if(nrow(done))return(invisible('unchanged'))
  x<-normalize_sdv_history(b,season);stopifnot(identical(attr(x,'signature'),sig))
  notes<-attr(x,'normalization_notes')
  folder<-file.path(directory,season,sig);dir.create(folder,recursive=TRUE,showWarnings=FALSE)
  manifests<-list();parents<-paste0('sdv:',names(b),':',season,':',vapply(b,`[[`,character(1),'sha256'))
  for(k in names(x))if('dataset_id'%in%names(x[[k]])) {
    id<-paste0('sdv-history:',k,':',season,':',sig);path<-file.path(folder,paste0(k,'.parquet'))
    arrow::write_parquet(x[[k]],path)
    manifests[[k]]<-data.frame(dataset_id=id,source_id='sportsdataverse',url=b$schedules$url,revision=paste0(archive_revision,':adapter:',sdv_history_version()),retrieved_at=Sys.time(),sha256=file_sha256(path),raw_path=path,row_count=nrow(x[[k]]))
  }
  index<-lapply(x,function(d)if('game_id'%in%names(d))split(seq_len(nrow(d)),d$game_id) else NULL)
  valid<-events<-character();statuses<-findings<-list()
  for(id in x$games$game_id) {
    one<-lapply(names(x),function(k)if(is.null(index[[k]]))x[[k]] else x[[k]][index[[k]][[id]],,drop=FALSE]);names(one)<-names(x)
    one$players<-one$players[one$players$player_id%in%one$player_box_scores$player_id,,drop=FALSE]
    one$player_identifiers<-one$player_identifiers[one$player_identifiers$player_id%in%one$players$player_id,,drop=FALSE]
    q<-sdv_box_quality(one);ok<-!any(q$severity=='error')
    if(ok)valid<-c(valid,id)
    full<-if(ok)quality_report(one) else q
    ep<-ok && nrow(one$pbp_events)>0 && !any(full$severity=='error')
    if(ep)events<-c(events,id)
    if(nrow(full))findings[[length(findings)+1L]]<-exception_rows(id,season,'sdv_history',full$check,paste('affected records:',full$count),full$severity,one$games$dataset_id[1])
    statuses[[length(statuses)+1L]]<-data.frame(game_id=id,season=season,signature=sig,box_status=if(ok)'observed' else 'failed_validation',event_status=if(!nrow(one$pbp_events))'source_missing' else if(ep)'observed' else 'failed_validation',shot_rows=if(ep)nrow(one$shot_attempts) else 0L,unknown_attempts=if(nrow(one$pbp_events))sum(sdv_attempt_features(one$pbp_events)$fg & is.na(one$pbp_events$points_attempted)) else 0L,completed_at=Sys.time())
  }
  state<-do.call(rbind,statuses)
  DBI::dbWithTransaction(con,{
    upsert_rows(con,'datasets',do.call(rbind,manifests),'dataset_id')
    dependencies<-do.call(rbind,lapply(manifests,function(m)data.frame(dataset_id=m$dataset_id,parent_dataset_id=parents,transformation='Historical adapter: explicit turnover-component semantics; unique attempt-count constraints; box and event gates separate')))
    upsert_rows(con,'dataset_dependencies',dependencies,c('dataset_id','parent_dataset_id'))
    if(length(findings))upsert_rows(con,'quality_exceptions',do.call(rbind,findings),'exception_id')
    if(nrow(notes))upsert_rows(con,'quality_exceptions',exception_rows(notes$game_id,season,'sdv_history_normalization',notes$rule,notes$detail,'warning',notes$dataset_id),'exception_id')
    protected<-DBI::dbGetQuery(con,"SELECT player_id FROM players")$player_id
    for(batch in split(valid,ceiling(seq_along(valid)/250L))) {
      z<-slice_games(x,batch)
      for(k in c('pbp_events','shot_attempts','substitutions'))z[[k]]<-z[[k]][z[[k]]$game_id%in%events,,drop=FALSE]
      DBI::dbWriteTable(con,'_sdv_history_games',z$games['game_id'],temporary=TRUE,overwrite=TRUE)
      DBI::dbExecute(con,'DELETE FROM lineup_players WHERE lineup_id IN (SELECT lineup_id FROM lineups WHERE game_id IN (SELECT game_id FROM _sdv_history_games))')
      for(k in c('lineups','possessions','possession_events','non_possession_points','lineup_minute_checks','reconstruction_status','pbp_reconciliation_checks','reconciliation_checks'))DBI::dbExecute(con,paste('DELETE FROM',k,'WHERE game_id IN (SELECT game_id FROM _sdv_history_games)'))
      for(k in names(z)) {
        if(k%in%c('players','player_identifiers'))z[[k]]<-z[[k]][!z[[k]]$player_id%in%protected,,drop=FALSE]
        if(k%in%c('player_box_scores','team_box_scores','pbp_events','shot_attempts','substitutions'))DBI::dbExecute(con,paste('DELETE FROM',k,'WHERE game_id IN (SELECT game_id FROM _sdv_history_games)'))
        upsert_rows(con,k,z[[k]],table_keys[[k]])
      }
    }
    g<-x$games;s<-b$schedules$data;s<-s[match(g$game_id,as.character(s$game_id)),]
    inventory<-data.frame(game_id=g$game_id,season=season,game_date=g$game_date,home_team_id=g$home_team_id,away_team_id=g$away_team_id,has_player_box=g$game_id%in%as.character(b$player_box$data$game_id),has_team_box=g$game_id%in%as.character(b$team_box$data$game_id),has_pbp=if(is.null(b$pbp))FALSE else g$game_id%in%as.character(b$pbp$data$game_id),validation_status=ifelse(g$game_id%in%valid,'passed','quarantined'),dataset_id=g$dataset_id,competition=g$competition)
    upsert_rows(con,'schedule_inventory',inventory,'game_id');upsert_rows(con,'sdv_history_status',state,'game_id')
    unavailable<-g$game_id[g$game_id%in%valid & !g$game_id%in%events]
    if(length(unavailable))upsert_rows(con,'reconstruction_status',data.frame(game_id=unavailable,season=season,version=reconstruction_version,possessions_status='unavailable_pbp',lineups_status='unavailable_pbp',resolved_team_periods=0L,expected_team_periods=0L,updated_at=Sys.time(),dataset_id=NA_character_,reference_signature='unavailable'),'game_id')
    upsert_rows(con,'sdv_history_checkpoints',data.frame(season=season,signature=sig,completed_at=Sys.time()),'season')
    assert_warehouse_integrity(con)
  })
  message(season,': ',length(valid),' boxes; ',length(events),' event games; ',sum(state$shot_rows),' shots admitted')
  invisible(state)
}
