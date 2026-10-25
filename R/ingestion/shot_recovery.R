shot_recovery_version <- function() {
  names<-c('shot_recovery_classify','shot_recovery_checks','shot_coordinate_evidence','stage_shot_recovery','shot_reference_observations','normalize_name','provider_id')
  inputs<-lapply(names,function(name)body(get(name,mode='function',inherits=TRUE)))
  substr(digest::digest(list(inputs,readLines('config/team_crosswalk.csv',warn=FALSE)),algo='sha256'),1,16)
}

shot_recovery_schema <- function(con) {
  DBI::dbExecute(con,'CREATE TABLE IF NOT EXISTS shot_recovery_checkpoints (season VARCHAR PRIMARY KEY,signature VARCHAR,method VARCHAR,rows BIGINT,completed_at TIMESTAMP)')
  DBI::dbExecute(con,'CREATE TABLE IF NOT EXISTS shot_recovery_candidates (season VARCHAR,game_id VARCHAR,event_id VARCHAR,source_row BIGINT,source_dataset_id VARCHAR,canonical_event_dataset_id VARCHAR,player_id VARCHAR,team_id VARCHAR,period INTEGER,clock VARCHAR,event_order INTEGER,made BOOLEAN,points_attempted INTEGER,value_status VARCHAR,classification_rule VARCHAR,x DOUBLE,y DOUBLE,raw_x DOUBLE,raw_y DOUBLE,coordinate_status VARCHAR,coordinate_system VARCHAR,certification_status VARCHAR,reason VARCHAR,dataset_id VARCHAR,PRIMARY KEY(dataset_id,source_row))')
  DBI::dbExecute(con,'CREATE TABLE IF NOT EXISTS shot_recovery_checks (season VARCHAR,game_id VARCHAR,team_id VARCHAR,metric VARCHAR,observed DOUBLE,expected DOUBLE,status VARCHAR,dataset_id VARCHAR,PRIMARY KEY(dataset_id,game_id,team_id,metric))')
  for(def in c('reference_snapshot_id VARCHAR','reference_source_row BIGINT','reference_event_id VARCHAR','reference_game_id VARCHAR','reference_player_id VARCHAR','identity_evidence VARCHAR','raw_transformed_x DOUBLE','raw_transformed_y DOUBLE','coordinate_frame_validated BOOLEAN','reference_outcome_checked BOOLEAN'))DBI::dbExecute(con,paste('ALTER TABLE shot_recovery_candidates ADD COLUMN IF NOT EXISTS',def))
}

stage_shot_recovery <- function(input,stage,season) {
  shot_recovery_schema(stage)
  source<-DBI::dbGetQuery(input,"SELECT DISTINCT d.* FROM datasets d WHERE d.dataset_id LIKE ?",params=list(paste0('sdv:pbp:',season,':%')))
  if(nrow(source)>1L)source<-source[source$raw_path==file.path('data/raw',archive_revision,paste0('play_by_play_',season_end(season),'.parquet')),,drop=FALSE]
  if(nrow(source)!=1L)stop('Exactly one pinned raw event snapshot required: ',season)
  stopifnot(file_sha256(source$raw_path)==source$sha256)
  e<-DBI::dbGetQuery(input,'SELECT e.* FROM pbp_events e JOIN games g USING(game_id) WHERE g.season=? ORDER BY e.game_id,e.event_order',params=list(season))
  box<-DBI::dbGetQuery(input,'SELECT t.* FROM team_box_scores t JOIN games g USING(game_id) WHERE g.season=? ORDER BY t.game_id,t.team_id',params=list(season))
  roster<-DBI::dbGetQuery(input,'SELECT p.*,n.name FROM player_box_scores p JOIN games g USING(game_id) JOIN players n USING(player_id) WHERE g.season=? ORDER BY p.game_id,p.player_id',params=list(season))
  games<-DBI::dbGetQuery(input,'SELECT * FROM games WHERE season=? ORDER BY game_id',params=list(season))
  reference_inputs<-list(snapshots=DBI::dbGetQuery(input,'SELECT snapshot_id,sha256 FROM historical_snapshots ORDER BY snapshot_id'),normalization=DBI::dbGetQuery(input,'SELECT DISTINCT transform_id FROM historical_checkpoints ORDER BY transform_id'))
  signature<-digest::digest(list(source$sha256,box,roster,games,e,reference_inputs,shot_recovery_version()),algo='sha256')
  if(nrow(DBI::dbGetQuery(stage,'SELECT * FROM shot_recovery_checkpoints WHERE season=? AND signature=?',params=list(season,signature))))return(invisible('unchanged'))
  raw<-arrow::read_parquet(source$raw_path,as_data_frame=FALSE)
  columns<-intersect(c('game_id','id','shooting_play','scoring_play','points_attempted','score_value','type_text','text','team_id','athlete_id_1','period_number','clock_display_value','game_play_number','coordinate_x','coordinate_y','coordinate_x_raw','coordinate_y_raw'),names(raw))
  raw<-as.data.frame(raw[columns]);raw[]<-lapply(raw,function(x)if(inherits(x,'integer64'))bit64::as.character.integer64(x) else x)
  if(!'points_attempted'%in%names(raw))raw$points_attempted<-NA_integer_
  key<-paste(e$game_id,e$event_id);j<-match(paste(raw$game_id,raw$id),key)
  r<-data.frame(game_id=as.character(raw$game_id),event_id=as.character(raw$id),shooting_play=raw$shooting_play,scoring_play=raw$scoring_play,score_value=raw$score_value,points_attempted=raw$points_attempted,event_type=raw$type_text,description=raw$text,team_id=provider_id(raw$team_id),player_id=provider_id(raw$athlete_id_1),period=as.integer(raw$period_number),clock=raw$clock_display_value,stringsAsFactors=FALSE)
  reference<-shot_reference_observations(input,season)
  classified<-shot_recovery_classify(r,box,reference);checks<-shot_recovery_checks(r,classified,box)
  passed<-names(Filter(function(z)nrow(z)==8L && all(z$status=='match'),split(checks,checks$game_id)))
  keep<-which(classified$fg);ri<-j[keep];raw_ids<-provider_id(raw$athlete_id_1[keep])
  pid<-e$player_id[ri];tid<-r$team_id[keep]
  matches<-!is.na(ri) & !is.na(pid) & !is.na(raw_ids) & pid==raw_ids & paste(r$game_id[keep],pid,tid)%in%paste(roster$game_id,roster$player_id,roster$team_id)
  context_matches<-!is.na(ri) & raw$period_number[keep]==e$period[ri] & raw$clock_display_value[keep]==e$clock[ri] & raw$type_text[keep]==e$event_type[ri] & raw$text[keep]==e$description[ri] & raw$scoring_play[keep]==e$scoring_play[ri] & raw$score_value[keep]==e$score_value[ri] & raw$game_play_number[keep]==e$event_order[ri] & tid==e$team_id[ri]
  context_matches[is.na(context_matches)]<-FALSE
  duplicate<-duplicated(paste(raw$game_id,raw$id)) | duplicated(paste(raw$game_id,raw$id),fromLast=TRUE)
  reason<-ifelse(is.na(ri),'source_event_not_in_canonical_pbp',ifelse(!matches,'unverified_player_or_team_mapping',ifelse(duplicate[keep],'duplicate_source_event',ifelse(classified$conflict[keep],'contradictory_attempt_value',ifelse(!r$game_id[keep]%in%passed,'game_shooting_totals_not_certified','')))))
  reason[!is.na(ri) & !context_matches]<-'source_context_differs_from_canonical_event'
  reason[is.na(raw$type_text[keep])]<-'missing_source_event_type'
  bad<-unique(r$game_id[keep][reason!='' & r$game_id[keep]%in%passed])
  reason[reason=='' & r$game_id[keep]%in%bad]<-'game_contains_unverified_shot_evidence'
  raw_x<-if('coordinate_x_raw'%in%names(raw))as.numeric(raw$coordinate_x_raw[keep]) else rep(NA_real_,length(keep))
  raw_y<-if('coordinate_y_raw'%in%names(raw))as.numeric(raw$coordinate_y_raw[keep]) else rep(NA_real_,length(keep))
  home<-r$team_id[keep]==games$home_team_id[match(r$game_id[keep],games$game_id)]
  location<-shot_coordinate_evidence(as.numeric(raw$coordinate_x[keep]),as.numeric(raw$coordinate_y[keep]),raw_x,raw_y,home)
  x<-location$x;y<-location$y;coordinate<-location$coordinate_status
  id<-paste0('shot-recovery:',season,':',signature)
  candidates<-data.frame(season=season,game_id=r$game_id[keep],event_id=r$event_id[keep],source_row=keep,source_dataset_id=source$dataset_id,canonical_event_dataset_id=e$dataset_id[ri],player_id=pid,team_id=tid,period=as.integer(raw$period_number[keep]),clock=raw$clock_display_value[keep],event_order=as.integer(raw$game_play_number[keep]),made=classified$made[keep],points_attempted=classified$value[keep],value_status=ifelse(is.na(classified$value[keep]),'source_missing',ifelse(classified$classification_rule[keep]%in%c('unique_box_attempt_constraints','unique_NBA_event_observation'),'reconstructed','observed')),classification_rule=classified$classification_rule[keep],x=x,y=y,raw_x=raw_x,raw_y=raw_y,coordinate_status=coordinate,coordinate_system=location$coordinate_system,certification_status=ifelse(reason=='','certified','noncertified'),reason=reason,dataset_id=id,stringsAsFactors=FALSE)
  ref<-classified$reference_row[keep]
  for(pair in list(c('snapshot_id','reference_snapshot_id'),c('source_row','reference_source_row'),c('nba_event_id','reference_event_id'),c('nba_game_id','reference_game_id'),c('nba_player_id','reference_player_id'),c('evidence','identity_evidence')))candidates[[pair[2]]]<-if(nrow(reference))reference[[pair[1]]][ref] else if(pair[2]=='reference_source_row')rep(NA_real_,length(keep)) else rep(NA_character_,length(keep))
  candidates$raw_transformed_x<-location$raw_transformed_x;candidates$raw_transformed_y<-location$raw_transformed_y;candidates$coordinate_frame_validated<-location$coordinate_frame_validated
  candidates$reference_outcome_checked<-classified$reference_outcome_checked[keep]
  checks$season<-season;checks$dataset_id<-id
  folder<-file.path('data/processed/phase3/shots',season,substr(signature,1,16));dir.create(folder,recursive=TRUE,showWarnings=FALSE)
  for(k in c('candidates','checks'))arrow::write_parquet(get(k),file.path(folder,paste0(k,'.parquet')))
  DBI::dbWithTransaction(stage,{
    for(t in c('shot_recovery_candidates','shot_recovery_checks'))DBI::dbExecute(stage,paste('DELETE FROM',t,'WHERE season=?'),params=list(season))
    DBI::dbAppendTable(stage,'shot_recovery_candidates',candidates);DBI::dbAppendTable(stage,'shot_recovery_checks',checks)
    upsert_rows(stage,'sources',DBI::dbReadTable(input,'sources'),'source_id')
    upsert_rows(stage,'datasets',source,'dataset_id')
    snapshots<-DBI::dbReadTable(input,'historical_snapshots')
    for(i in seq_len(nrow(snapshots))) {
      p<-snapshots[i,]
      upsert_rows(stage,'datasets',data.frame(dataset_id=p$snapshot_id,source_id=p$source_id,url=p$url,revision=p$revision,retrieved_at=file.info(p$path)$mtime,sha256=p$sha256,raw_path=p$path,row_count=p$raw_rows),'dataset_id')
    }
    manifests<-do.call(rbind,lapply(c('candidates','checks'),function(k){p<-file.path(folder,paste0(k,'.parquet'));data.frame(dataset_id=paste0(id,':',k),source_id=source$source_id,url=source$url,revision=paste0('shot-recovery-',shot_recovery_version()),retrieved_at=Sys.time(),sha256=file_sha256(p),raw_path=p,row_count=nrow(get(k)))}))
    upsert_rows(stage,'datasets',manifests,'dataset_id')
    parents<-unique(c(source$dataset_id,box$dataset_id,e$dataset_id,reference_inputs$snapshots$snapshot_id))
    upsert_rows(stage,'dataset_dependencies',do.call(rbind,lapply(manifests$dataset_id,function(d)data.frame(dataset_id=d,parent_dataset_id=parents,transformation='Recorded FG flags excluding FTs; explicit or uniquely constrained attempt values; four box count checks; exact native IDs; raw ordering preserved'))),c('dataset_id','parent_dataset_id'))
    upsert_rows(stage,'shot_recovery_checkpoints',data.frame(season=season,signature=signature,method=shot_recovery_version(),rows=nrow(candidates),completed_at=Sys.time()),'season')
  })
  message(season,': ',nrow(candidates),' observed FG candidates; ',sum(candidates$certification_status=='certified'),' certified; ',length(passed),' count-matched games')
  invisible(candidates)
}
