nba_recovery_player_map <- function(nba,espn,names) {
  literal<-function(x)tolower(trimws(gsub('[[:space:]]+',' ',x)))
  nba$name<-names$name[match(nba$player_id,names$player_id)]
  a<-paste(nba$team_id,literal(nba$name));b<-paste(espn$team_id,literal(espn$name))
  if(anyNA(nba$name) || anyDuplicated(a) || any(vapply(a,function(key)sum(b==key),integer(1))!=1L))return(NULL)
  j<-match(a,b);if(anyNA(j) || anyNA(espn$player_id[j]))return(NULL)
  for(m in c('points','fgm','fga','fg3m','fg3a','ftm','fta','assists','turnovers','rebounds')) {
    known<-!is.na(espn[[m]][j])
    if(anyNA(nba[[m]]) || any(nba[[m]][known]!=espn[[m]][j][known]))return(NULL)
  }
  if(any(espn$did_not_play[j]%in%TRUE & nba$minutes>0,na.rm=TRUE))return(NULL)
  if('confirmed_dnp'%in%names(nba) && any(nba$confirmed_dnp & espn$minutes[j]>0,na.rm=TRUE))return(NULL)
  known_minutes<-!is.na(espn$minutes[j]) & !is.na(nba$minutes)
  tolerance<-ifelse(abs(espn$minutes[j]-round(espn$minutes[j]))<1e-8,1,1.01/60)
  if(any(abs(nba$minutes[known_minutes]-espn$minutes[j][known_minutes])>tolerance[known_minutes]))return(NULL)
  data.frame(nba_player_id=nba$player_id,player_id=espn$player_id[j],nba_name=nba$name,espn_name=espn$name[j],team_id=nba$team_id,stringsAsFactors=FALSE)
}

recover_sdv_nba_boxes <- function(con,seasons) {
  historical_game_links(con)
  DBI::dbExecute(con,'CREATE TABLE IF NOT EXISTS sdv_nba_player_links (game_id VARCHAR,nba_game_id VARCHAR,nba_player_id VARCHAR,player_id VARCHAR,nba_name VARCHAR,espn_name VARCHAR,team_id VARCHAR,evidence VARCHAR,PRIMARY KEY(game_id,nba_player_id))')
  map<-utils::read.csv('config/team_crosswalk.csv',colClasses='character')
  names<-DBI::dbReadTable(con,'historical_players')
  player_file<-DBI::dbGetQuery(con,"SELECT path FROM historical_snapshots WHERE kind='player'")$path
  DBI::dbExecute(con,paste0("CREATE OR REPLACE TEMP TABLE _nba_explicit_nonplaying AS SELECT 'nba:'||",historical_sql_id('gameId')," game_id,'nba:'||personId player_id,comment FROM read_csv(",DBI::dbQuoteString(con,normalizePath(player_file,winslash='/')) ,",all_varchar=TRUE) WHERE regexp_matches(coalesce(comment,''),'(?i)DNP|DND|inactive|not with|not dressed') QUALIFY count(*) OVER(PARTITION BY gameId,personId)=1"))
  dnp<-DBI::dbGetQuery(con,'SELECT * FROM _nba_explicit_nonplaying')
  snapshots<-DBI::dbReadTable(con,'historical_snapshots');parents<-snapshots[snapshots$kind%in%c('games','team','player','players'),]
  for(i in seq_len(nrow(parents))) {
    z<-parents[i,]
    upsert_rows(con,'datasets',data.frame(dataset_id=z$snapshot_id,source_id='eoin_moore_nba',url=z$url,revision=z$revision,retrieved_at=file.info(z$path)$mtime,sha256=z$sha256,raw_path=z$path,row_count=z$raw_rows),'dataset_id')
  }
  recovered<-character()
  for(season in seasons) {
    candidates<-DBI::dbGetQuery(con,"SELECT s.game_id,l.nba_game_id FROM sdv_history_status s JOIN historical_game_links l ON s.game_id=l.espn_game_id WHERE s.season=? AND s.box_status='failed_validation'",params=list(season))
    if(!nrow(candidates))next
    message(season,': checking ',nrow(candidates),' unresolved box families')
    b<-fetch_sdv_history(season)
    saved<-DBI::dbGetQuery(con,'SELECT signature FROM sdv_history_checkpoints WHERE season=?',params=list(season))$signature
    if(length(saved)!=1L)stop('Historical source normalization must finish before recovery')
    # Reuse the exact normalized full-family snapshots, including failed games.
    # This avoids repeating classification and preserves mixed-calendar fixes.
    x<-list(seasons=data.frame(season=season,end_year=season_end(season)))
    for(k in c('games','player_box_scores','team_box_scores','pbp_events','shot_attempts','substitutions')) {
      path<-DBI::dbGetQuery(con,'SELECT raw_path FROM datasets WHERE dataset_id=?',params=list(paste0('sdv-history:',k,':',season,':',saved)))$raw_path
      if(length(path)!=1L)stop('Missing normalized recovery input: ',k)
      x[[k]]<-as.data.frame(arrow::read_parquet(path))
    }
    s<-b$schedules$data;s<-s[match(x$games$game_id,as.character(s$game_id)),]
    x$team_identities<-unique(rbind(data.frame(team_id=provider_id(s$home_id),season=season,abbreviation=s$home_abbreviation,name=s$home_display_name),data.frame(team_id=provider_id(s$away_id),season=season,abbreviation=s$away_abbreviation,name=s$away_display_name)))
    x$team_identities<-x$team_identities[!duplicated(x$team_identities[c('team_id','season')]),]
    x$teams<-unique(data.frame(team_id=x$team_identities$team_id,provider='espn'))
    raw_p<-b$player_box$data
    x$players<-data.frame(player_id=provider_id(raw_p$athlete_id),name=raw_p$athlete_display_name,search_name=normalize_name(raw_p$athlete_display_name))
    x$players<-x$players[!duplicated(x$players$player_id) & !is.na(x$players$player_id),]
    x$player_identifiers<-data.frame(provider='espn',provider_id=sub('espn:','',x$players$player_id),player_id=x$players$player_id)
    attr(x,'signature')<-saved
    indices<-lapply(x,function(d)if('game_id'%in%names(d))split(seq_len(nrow(d)),d$game_id) else NULL)
    nt<-DBI::dbGetQuery(con,'SELECT * FROM historical_team_boxes WHERE season=?',params=list(season))
    np<-DBI::dbGetQuery(con,'SELECT * FROM historical_player_boxes WHERE season=?',params=list(season))
    nt$team_id<-paste0('espn:',map$espn_id[match(sub('nba:','',nt$team_id),map$nba_id)])
    np$team_id<-paste0('espn:',map$espn_id[match(sub('nba:','',np$team_id),map$nba_id)])
    team_index<-split(seq_len(nrow(nt)),nt$game_id)
    player_index<-split(seq_len(nrow(np)),np$game_id)
    accepted<-links<-list()
    for(i in seq_len(nrow(candidates))) {
      id<-candidates$game_id[i];nid<-candidates$nba_game_id[i]
      t<-nt[team_index[[nid]],,drop=FALSE];p<-np[player_index[[nid]],,drop=FALSE]
      metrics<-c('points','fgm','fga','fg3m','fg3a','ftm','fta','assists','turnovers','rebounds','minutes')
      p$confirmed_dnp<-paste(p$game_id,p$player_id)%in%paste(dnp$game_id,dnp$player_id)
      if(nrow(t)!=2L || any(t$validation_status!='observed') || nrow(p)<10L || any(p$validation_status!='observed') || anyNA(p[setdiff(metrics,'minutes')]) || any(is.na(p$minutes) & !p$confirmed_dnp))next
      if(any(p$confirmed_dnp & rowSums(p[c('points','fgm','fga','fg3m','fg3a','ftm','fta','assists','turnovers','rebounds')])!=0))next
      one<-lapply(names(x),function(k)if(is.null(indices[[k]]))x[[k]] else x[[k]][indices[[k]][[id]],,drop=FALSE]);names(one)<-names(x)
      one$players<-one$players[one$players$player_id%in%one$player_box_scores$player_id,,drop=FALSE]
      one$player_identifiers<-one$player_identifiers[one$player_identifiers$player_id%in%one$players$player_id,,drop=FALSE]
      old<-one$player_box_scores
      if(any(table(factor(p$team_id,levels=t$team_id))<5L))next
      expected_minutes<-if(nrow(one$pbp_events))rep((48+max(0,max(one$pbp_events$period)-4L)*5)*5,2) else t$minutes
      if(anyNA(expected_minutes))next
      minute_ok<-vapply(seq_len(nrow(t)),function(k) {
        v<-p$minutes[p$team_id==t$team_id[k] & !p$confirmed_dnp]
        tolerance<-sum(ifelse(abs(v-round(v))<1e-8,1,1.01/60))
        !anyNA(v) && abs(sum(v)-expected_minutes[k])<=tolerance
      },logical(1))
      if(!all(minute_ok))next
      old$name<-one$players$name[match(old$player_id,one$players$player_id)]
      identity<-nba_recovery_player_map(p,old,names)
      if(is.null(identity))next
      people<-unique(c(one$pbp_events$player_id,one$pbp_events$secondary_player_id,one$pbp_events$tertiary_player_id))
      if(any(identity$player_id[p$confirmed_dnp]%in%people))next
      # Native NBA rows replace the entire invalid box family. Known ESPN
      # player counts must agree; no cells are patched to force a pass.
      pb<-p[c('team_id','minutes','fgm','fga','fg3m','fg3a','ftm','fta','points','assists','turnovers','rebounds')]
      pb$game_id<-id;pb$player_id<-identity$player_id;pb$did_not_play<-ifelse(p$confirmed_dnp,TRUE,ifelse(pb$minutes>0,FALSE,NA))
      pb$starter<-old$starter[match(pb$player_id,old$player_id)]
      tb<-t[c('team_id','points','fgm','fga','fg3m','fg3a','ftm','fta','assists')];tb$game_id<-id
      tb$turnovers<-vapply(tb$team_id,function(team)as.integer(sum(pb$turnovers[pb$team_id==team])),integer(1))
      tb$total_turnovers<-ifelse(!is.na(t$turnovers) & t$turnovers>=tb$turnovers,as.integer(t$turnovers),NA_integer_)
      token<-substr(digest::digest(list(id,parents$sha256,attr(x,'signature'),body(nba_recovery_player_map)),algo='sha256'),1,24)
      pb$dataset_id<-paste0('nba-recovery:players:',token);tb$dataset_id<-paste0('nba-recovery:teams:',token)
      one$player_box_scores<-pb;one$team_box_scores<-tb
      one$players<-one$players[one$players$player_id%in%pb$player_id,,drop=FALSE]
      one$player_identifiers<-one$player_identifiers[one$player_identifiers$player_id%in%pb$player_id,,drop=FALSE]
      q<-sdv_box_quality(one);if(any(q$severity=='error'))next
      full<-quality_report(one);ep<-nrow(one$pbp_events)>0 && !any(full$severity=='error')
      if(!ep)for(k in c('pbp_events','shot_attempts','substitutions'))one[[k]]<-one[[k]][FALSE,,drop=FALSE]
      folder<-file.path('data/processed/sdv_nba_recovery',season,token);dir.create(folder,recursive=TRUE,showWarnings=FALSE)
      manifests<-dependencies<-list()
      for(k in c('player_box_scores','team_box_scores')) {
        d<-one[[k]];path<-file.path(folder,paste0(k,'.parquet'));arrow::write_parquet(d,path)
        manifests[[k]]<-data.frame(dataset_id=unique(d$dataset_id),source_id='eoin_moore_nba',url=parents$url[1],revision='kaggle-v524-exact-identity-recovery',retrieved_at=Sys.time(),sha256=file_sha256(path),raw_path=path,row_count=nrow(d))
        raw_parents<-c(parents$snapshot_id,paste0('sdv:player_box:',season,':',b$player_box$sha256),paste0('sdv:schedules:',season,':',b$schedules$sha256))
        dependencies[[k]]<-data.frame(dataset_id=unique(d$dataset_id),parent_dataset_id=raw_parents,transformation='Whole NBA box recovery; unique exact name/game/mapped team identities; every available ESPN player count agrees; not independent of NBA reference')
      }
      accepted[[id]]<-list(x=one,events=ep,report=q,manifests=do.call(rbind,manifests),dependencies=do.call(rbind,dependencies))
      identity$game_id<-id;identity$nba_game_id<-nid;identity$evidence<-'unique exact full name/game/mapped team; every available ESPN count agrees'
      links[[id]]<-identity
    }
    if(!length(accepted))next
    identity<-do.call(rbind,links)
    # Reject inconsistent cross-game player mappings rather than guessing.
    bad_nba<-names(Filter(function(z)length(unique(z))!=1L,split(identity$player_id,identity$nba_player_id)))
    bad_espn<-names(Filter(function(z)length(unique(z))!=1L,split(identity$nba_player_id,identity$player_id)))
    blocked<-unique(identity$game_id[identity$nba_player_id%in%bad_nba | identity$player_id%in%bad_espn])
    for(batch in split(setdiff(names(accepted),blocked),ceiling(seq_along(setdiff(names(accepted),blocked))/100L))) {
      upsert_rows(con,'datasets',do.call(rbind,lapply(accepted[batch],`[[`,'manifests')),'dataset_id')
      upsert_rows(con,'dataset_dependencies',do.call(rbind,lapply(accepted[batch],`[[`,'dependencies')),c('dataset_id','parent_dataset_id'))
      z<-lapply(names(x),function(k)unique(do.call(rbind,lapply(accepted[batch],function(a)a$x[[k]]))));names(z)<-names(x)
      z$players<-z$players[!duplicated(z$players$player_id),];z$player_identifiers<-z$player_identifiers[!duplicated(z$player_identifiers[c('provider','provider_id')]),]
      DBI::dbExecute(con,'CREATE OR REPLACE TEMP TABLE _recovery_preserved_players AS SELECT * FROM players')
      ingest_bundle(con,b,season,normalized=z,validated_report=do.call(rbind,lapply(accepted[batch],`[[`,'report')))
      DBI::dbExecute(con,'UPDATE players p SET name=o.name,search_name=o.search_name FROM _recovery_preserved_players o WHERE p.player_id=o.player_id')
      upsert_rows(con,'sdv_nba_player_links',identity[identity$game_id%in%batch,],c('game_id','nba_player_id'))
      state<-do.call(rbind,lapply(batch,function(id)data.frame(game_id=id,event_status=if(accepted[[id]]$events)'observed' else 'source_missing',shot_rows=nrow(accepted[[id]]$x$shot_attempts))))
      DBI::dbWriteTable(con,'_recovery_status',state,temporary=TRUE,overwrite=TRUE)
      DBI::dbExecute(con,"UPDATE sdv_history_status s SET box_status='reconstructed',event_status=r.event_status,shot_rows=r.shot_rows,completed_at=current_timestamp FROM _recovery_status r WHERE s.game_id=r.game_id")
      DBI::dbExecute(con,"UPDATE schedule_inventory SET validation_status='passed_reference_box' WHERE game_id IN (SELECT game_id FROM _recovery_status)")
      unavailable<-state$game_id[state$event_status!='observed']
      if(length(unavailable))upsert_rows(con,'reconstruction_status',data.frame(game_id=unavailable,season=season,version=reconstruction_version,possessions_status='unavailable_pbp',lineups_status='unavailable_pbp',resolved_team_periods=0L,expected_team_periods=0L,updated_at=Sys.time(),reference_signature='unavailable'),'game_id')
      recovered<-c(recovered,batch)
      message(season,': published ',length(recovered),' recovered boxes this run')
    }
    assert_warehouse_integrity(con)
    message(season,': ',sum(!names(accepted)%in%blocked),' whole NBA boxes recovered')
  }
  invisible(recovered)
}
