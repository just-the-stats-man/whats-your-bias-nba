sdv_history_version <- function() {
  # Resolve fingerprint inputs by name: static targets dependency discovery
  # must not interpret a body hash as a recursive execution dependency.
  inputs<-c('sdv_attempt_features','normalize_sdv_history','sdv_box_quality','ingest_sdv_history','quality_report')
  bodies<-lapply(inputs,function(name)body(get(name,mode='function',inherits=TRUE)))
  substr(digest::digest(c(bodies,list(reconstruction_version)),algo='sha256'),1,16)
}

sdv_attempt_features <- function(e) {
  fg<-e$shooting_play%in%TRUE & !grepl('free throw',e$event_type,ignore.case=TRUE)
  made<-e$scoring_play%in%TRUE;value<-as.integer(e$points_attempted)
  value[!value%in%c(2L,3L)]<-NA_integer_
  explicit<-fg & made & e$score_value%in%c(2L,3L)
  value[explicit]<-as.integer(e$score_value[explicit])
  unknown<-fg & is.na(value);text<-tolower(e$description)
  three<-grepl('three.point|3.point|3.pt|three pointer',text)
  two<-grepl('two.point|2.point|layup|lay up|dunk|tip shot|hook shot',text)
  value[unknown & three]<-3L;value[unknown & !three & two]<-2L
  list(fg=fg,made=made,value=value)
}

normalize_sdv_history <- function(bundle,season) {
  if(season_end(season)>=2016L)stop('Historical adapter cannot replace verified modern inputs')
  original<-bundle
  if(is.null(bundle$pbp))bundle$pbp<-list(data=readRDS('data/sample/bundle.rds')$pbp$data[FALSE,],sha256='absent',path=NA_character_)
  x<-normalize_bundle(bundle,season)
  notes<-attr(x,'normalization_notes')
  added_notes<-list()
  note<-function(game_id,rule,detail,dataset_id) {
    added_notes[[length(added_notes)+1L]]<<-data.frame(game_id=game_id,rule=rule,detail=detail,dataset_id=dataset_id)
  }
  # Canonical turnovers are player turnovers. These old ESPN rows duplicate
  # their reported aggregate in team_turnovers, then add it a second time.
  # Keep that reported aggregate as total; derive the player component only
  # from complete observed player records. No missing component becomes zero.
  raw<-bundle$team_box$data;t<-x$team_box_scores;p<-x$player_box_scores
  key<-paste(raw$game_id,provider_id(raw$team_id));idx<-match(paste(t$game_id,t$team_id),key)
  duplicate<-if(all(c('team_turnovers','total_turnovers')%in%names(raw))) !is.na(idx) & raw$team_turnovers[idx]==raw$turnovers[idx] & raw$total_turnovers[idx]==2*raw$turnovers[idx] else rep(FALSE,nrow(t))
  groups<-split(seq_len(nrow(p)),paste(p$game_id,p$team_id))
  for(i in which(duplicate%in%TRUE)) {
    rows<-groups[[paste(t$game_id[i],t$team_id[i])]]
    values<-p$turnovers[rows][!p$did_not_play[rows]%in%TRUE]
    if(!length(values) || anyNA(values) || any(values<0))next
    player_sum<-sum(values);reported<-raw$turnovers[idx[i]]
    if(is.na(reported) || reported<player_sum)next
    t$turnovers[i]<-as.integer(player_sum);t$total_turnovers[i]<-as.integer(reported)
    note(t$game_id[i],'historical_turnover_components',paste(t$team_id[i],'recorded aggregate',reported,'player sum',player_sum,'duplicated raw component retained in source'),t$dataset_id[i])
  }
  x$team_box_scores<-t
  x$team_identities<-x$team_identities[!duplicated(x$team_identities[c('team_id','season')],fromLast=TRUE),,drop=FALSE]
  e<-x$pbp_events
  if(nrow(e)) {
    f<-sdv_attempt_features(e)
    value<-f$value;attempts<-split(which(f$fg),paste(e$game_id[f$fg],e$team_id[f$fg]))
    # A count constraint classifies unknown attempts only when the assignment
    # is UNIQUE: all remaining shots are twos, or all are threes. Mixed
    # assignments remain unavailable. Require complete FGA/FGM/3PM identities.
    for(i in seq_len(nrow(t))) {
      ix<-attempts[[paste(t$game_id[i],t$team_id[i])]]
      unknown<-ix[is.na(value[ix])]
      counts<-t[i,c('fga','fgm','fg3m','fg3a')]
      if(!length(unknown) || anyNA(counts) || length(ix)!=t$fga[i] || sum(f$made[ix])!=t$fgm[i])next
      if(any(f$made[unknown]) || sum(f$made[ix] & value[ix]%in%3L)!=t$fg3m[i])next
      remaining<-t$fg3a[i]-sum(value[ix]%in%3L)
      if(!remaining%in%c(0L,length(unknown)))next
      value[unknown]<-if(remaining==0L)2L else 3L
      note(e$game_id[unknown],'unique_attempt_count_constraint',paste('event',e$event_id[unknown],'value',value[unknown],'unique remaining FGA/3PA assignment;',t$team_id[i]),e$dataset_id[unknown])
    }
    e$points_attempted<-value
    x$pbp_events<-e
    fg<-f$fg & value%in%c(2L,3L)
    raw_e<-bundle$pbp$data;j<-match(paste(e$game_id,e$event_id),paste(raw_e$game_id,as.character(raw_e$id)))
    # Use normalized IDs: integer64 event keys are converted by normalize_bundle.
    if(inherits(raw_e$id,'integer64'))j<-match(paste(e$game_id,e$event_id),paste(raw_e$game_id,bit64::as.character.integer64(raw_e$id)))
    shots<-data.frame(game_id=e$game_id[fg],event_id=e$event_id[fg],player_id=e$player_id[fg],team_id=e$team_id[fg],points_attempted=as.integer(value[fg]),made=f$made[fg],x=as.numeric(raw_e$coordinate_x[j[fg]]),y=as.numeric(raw_e$coordinate_y[j[fg]]),coordinate_system='sportsdataverse ESPN transformed; uncalibrated',observation_type=ifelse(is.na(f$value[fg]),'reconstructed_unique_attempt_constraints','provider_attributed'),dataset_id=e$dataset_id[fg])
    shots$x[abs(shots$x)>100]<-NA_real_;shots$y[abs(shots$y)>100]<-NA_real_
    x$shot_attempts<-shots
  }
  signature<-substr(digest::digest(list(vapply(original,`[[`,character(1),'sha256'),sdv_history_version()),algo='sha256'),1,24)
  for(table in names(x))if('dataset_id'%in%names(x[[table]]))x[[table]]$dataset_id<-rep(paste0('sdv-history:',table,':',season,':',signature),nrow(x[[table]]))
  attr(x,'normalization_notes')<-if(length(added_notes))do.call(rbind,c(list(notes),added_notes)) else notes
  attr(x,'signature')<-signature
  x
}

sdv_box_quality <- function(x) {
  for(k in c('pbp_events','shot_attempts','substitutions'))x[[k]]<-x[[k]][FALSE,,drop=FALSE]
  q<-quality_report(x)
  q[q$check!='missing play-by-play',,drop=FALSE]
}
