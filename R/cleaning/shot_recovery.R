shot_recovery_classify <- function(e,box,reference=NULL) {
  n<-nrow(e);type<-tolower(e$event_type);text<-tolower(e$description)
  ft<-grepl('free[[:space:]_-]*throw',type)
  fg<-e$shooting_play%in%TRUE & !ft
  value<-as.integer(e$points_attempted);value[!value%in%c(2L,3L)]<-NA_integer_
  rule<-ifelse(!is.na(value),'source_attempt_annotation','source_missing')
  conflict<-fg & e$scoring_play%in%TRUE & e$score_value%in%c(2,3) & !is.na(value) & value!=e$score_value
  made<-as.logical(e$scoring_play)
  ix<-which(fg & made%in%TRUE & is.na(value) & e$score_value%in%c(2,3))
  value[ix]<-as.integer(e$score_value[ix]);rule[ix]<-'source_made_value'
  three<-grepl('three[ -]point|3[ -]point|3[ -]pt|three pointer',text)
  two<-grepl('two[ -]point|2[ -]point|lay[ -]?up|dunk|tip shot|hook shot',text)
  ix<-which(fg & is.na(value) & (three|two))
  value[ix]<-ifelse(three[ix],3L,2L);rule[ix]<-'explicit_source_description'
  reference_row<-rep(NA_integer_,n)
  outcome_checked<-rep(FALSE,n)
  if(!is.null(reference) && nrow(reference)) {
    clock<-function(x)vapply(strsplit(as.character(x),':',fixed=TRUE),function(v)if(length(v)==2L)as.numeric(v[1])*60+as.numeric(v[2]) else NA_real_,numeric(1))
    a<-paste(e$game_id,e$team_id,e$player_id,e$period,clock(e$clock),made)
    b<-paste(reference$game_id,reference$team_id,reference$player_id,reference$period,reference$clock_seconds,reference$made)
    unique_a<-!duplicated(a) & !duplicated(a,fromLast=TRUE)
    unique_b<-!duplicated(b) & !duplicated(b,fromLast=TRUE)
    j<-match(a,b);good<-fg & unique_a & !is.na(j) & unique_b[j]
    good[is.na(good)]<-FALSE;reference_row[good]<-j[good]
    base_a<-paste(e$game_id,e$team_id,e$player_id,e$period,clock(e$clock))
    base_b<-paste(reference$game_id,reference$team_id,reference$player_id,reference$period,reference$clock_seconds)
    base_j<-match(base_a,base_b)
    unique_base<-fg & !duplicated(base_a) & !duplicated(base_a,fromLast=TRUE) & !is.na(base_j) & !duplicated(base_b)[base_j] & !duplicated(base_b,fromLast=TRUE)[base_j]
    unique_base[is.na(unique_base)]<-FALSE;outcome_checked[unique_base]<-TRUE;reference_row[unique_base]<-base_j[unique_base]
    conflict<-conflict | (unique_base & made!=reference$made[base_j])%in%TRUE
    disagreement<-good & !is.na(value) & value!=reference$points_attempted[j]
    conflict<-conflict | disagreement%in%TRUE
    ix<-which(good & !conflict%in%TRUE & is.na(value));value[ix]<-reference$points_attempted[j[ix]];rule[ix]<-'unique_NBA_event_observation'
  }
  groups<-split(which(fg),paste(e$game_id[fg],e$team_id[fg]))
  for(i in seq_len(nrow(box))) {
    ix<-groups[[paste(box$game_id[i],box$team_id[i])]]
    if(!length(ix) || anyNA(box[i,c('fga','fgm','fg3a','fg3m')]) || length(ix)!=box$fga[i] || anyNA(made[ix]) || sum(made[ix])!=box$fgm[i] || any(conflict[ix]%in%TRUE))next
    # Outcomes partition the constraints. Assign a type only if EVERY unknown
    # in its outcome group has the same uniquely implied two/three value.
    for(outcome in c(TRUE,FALSE)) {
      sub<-ix[made[ix]==outcome];unknown<-sub[is.na(value[sub])]
      expected<-if(outcome)box$fg3m[i] else box$fg3a[i]-box$fg3m[i]
      remaining<-expected-sum(value[sub]%in%3L)
      if(length(unknown) && remaining%in%c(0L,length(unknown))) {
        value[unknown]<-if(remaining==0L)2L else 3L;rule[unknown]<-'unique_box_attempt_constraints'
      }
    }
  }
  data.frame(fg=fg,free_throw=ft,made=made,value=value,classification_rule=rule,conflict=conflict%in%TRUE,reference_row=reference_row,reference_outcome_checked=outcome_checked,stringsAsFactors=FALSE)
}

shot_recovery_checks <- function(e,classification,box) {
  groups<-split(which(classification$fg),paste(e$game_id[classification$fg],e$team_id[classification$fg]))
  rows<-lapply(seq_len(nrow(box)),function(i) {
    ix<-groups[[paste(box$game_id[i],box$team_id[i])]];f<-classification[ix,,drop=FALSE]
    observed<-c(fga=length(ix),fgm=if(anyNA(f$made))NA_real_ else sum(f$made),fg3a=if(anyNA(f$value))NA_real_ else sum(f$value==3),fg3m=if(anyNA(f$made) || anyNA(f$value[f$made%in%TRUE]))NA_real_ else sum(f$made%in%TRUE & f$value%in%3))
    do.call(rbind,lapply(names(observed),function(m)data.frame(game_id=box$game_id[i],team_id=box$team_id[i],metric=m,observed=observed[[m]],expected=box[[m]][i],status=if(is.na(observed[[m]]) || is.na(box[[m]][i]))'source_missing' else if(observed[[m]]==box[[m]][i])'match' else 'failed_validation')))
  })
  if(length(rows))do.call(rbind,rows) else data.frame(game_id=character(),team_id=character(),metric=character(),observed=double(),expected=double(),status=character())
}

shot_coordinate_evidence <- function(x,y,raw_x,raw_y,home) {
  # Identify the publisher's existing transform; never rotate or infer points.
  # hoopR helper_espn_nba_pbp: home x=41.75-raw_y,y=25-raw_x;
  # away has the opposite signs. Feet, court centered, home attacks +x.
  expected_x<-ifelse(home,41.75-raw_y,raw_y-41.75)
  expected_y<-ifelse(home,25-raw_x,raw_x-25)
  missing<-is.na(x)|is.na(y)
  native_missing<-is.na(raw_x)|is.na(raw_y)|is.na(home)
  valid<-!missing & !native_missing & is.finite(x) & is.finite(y) & abs(x)<=47 & abs(y)<=25 & abs(x-expected_x)<1e-6 & abs(y-expected_y)<1e-6
  valid[is.na(valid)]<-FALSE
  status<-ifelse(missing|native_missing,'source_missing',ifelse(valid,'observed','failed_validation'))
  data.frame(x=ifelse(valid,x,NA_real_),y=ifelse(valid,y,NA_real_),raw_transformed_x=x,raw_transformed_y=y,coordinate_status=status,coordinate_frame_validated=valid,coordinate_system=ifelse(valid,'espn_hoopr_centered_feet_home_positive','source_frame_unverified'),stringsAsFactors=FALSE)
}
