phase4_shot_method <- function() paste0('terminal-shots-v1-',substr(digest::digest(list(shot_recovery_version(),body(terminal_score_evidence),body(terminal_shot_references),body(stage_terminal_shot_game)),algo='sha256'),1,16))

terminal_shot_references <- function(con,season) {
  # Reuse precisely the Phase 3 identity/count/minute gates. Its player links
  # cover the entire season, including games rejected only by the old score rule.
  old<-shot_reference_observations(con,season);links<-attr(old,'player_links')
  terminal<-terminal_score_evidence(con,season)
  if(is.null(links)||!nrow(links)||!nrow(terminal))return(list(reference=old,terminal=terminal))
  DBI::dbWriteTable(con,'_terminal_score_evidence',terminal,temporary=TRUE,overwrite=TRUE)
  extra<-DBI::dbGetQuery(con,"WITH shooting AS (SELECT game_id FROM historical_event_checks WHERE season=? AND metric!='points' GROUP BY game_id HAVING count(*)=8 AND bool_and(status='reconstructed')), old AS (SELECT game_id FROM historical_event_checks WHERE season=? GROUP BY game_id HAVING count(*)=10 AND bool_and(status='reconstructed')) SELECT l.game_id,l.player_id,l.team_id,e.period,e.clock,s.made,s.points_attempted,s.snapshot_id,s.source_row,e.event_id nba_event_id,l.nba_game_id,l.nba_player_id,l.evidence FROM historical_shots s JOIN historical_events e USING(snapshot_id,source_row) JOIN shooting q ON s.game_id=q.game_id JOIN _terminal_score_evidence t ON s.game_id=t.game_id JOIN _shot_player_links l ON s.game_id=l.nba_game_id AND s.player_id=l.nba_player_id WHERE s.season=? AND e.season=? AND t.eligible AND s.points_status='observed' AND s.made IS NOT NULL AND NOT EXISTS(SELECT 1 FROM old WHERE old.game_id=s.game_id)",params=list(season,season,season,season))
  if(nrow(extra)) {
    clocks<-sub('^PT([0-9]+)M([0-9.]+)S$','\\1:\\2',extra$clock)
    extra$clock_seconds<-vapply(strsplit(clocks,':',fixed=TRUE),function(v)if(length(v)==2L)as.numeric(v[1])*60+as.numeric(v[2]) else NA_real_,numeric(1))
    extra<-extra[!is.na(extra$clock_seconds),,drop=FALSE]
    old<-rbind(old,extra)
  }
  list(reference=old,terminal=terminal,links=links)
}

stage_terminal_shot_game <- function(candidates,events,box,reference,terminal,method=phase4_shot_method()) {
  stopifnot(length(unique(candidates$game_id))==1L,!any(candidates$certification_status=='certified'))
  id<-candidates$game_id[1];candidates<-candidates[order(candidates$event_order,candidates$event_id),,drop=FALSE]
  reference<-reference[reference$game_id==id,,drop=FALSE]
  reference<-reference[order(reference$snapshot_id,reference$source_row),,drop=FALSE]
  terminal<-terminal[terminal$game_id%in%reference$nba_game_id,,drop=FALSE]
  terminal<-terminal[order(terminal$game_id,terminal$snapshot_id,terminal$source_row),,drop=FALSE]
  signature<-digest::digest(list(candidates,events,box,reference,terminal,method),algo='sha256')
  j<-match(candidates$event_id,events$event_id)
  stopifnot(!anyNA(j),!anyDuplicated(candidates$event_id))
  e<-data.frame(game_id=id,event_id=candidates$event_id,shooting_play=TRUE,scoring_play=candidates$made,score_value=events$score_value[j],points_attempted=candidates$points_attempted,event_type=events$event_type[j],description=events$description[j],team_id=candidates$team_id,player_id=candidates$player_id,period=candidates$period,clock=candidates$clock)
  f<-shot_recovery_classify(e,box,reference);checks<-shot_recovery_checks(e,f,box)
  changed<-is.na(candidates$points_attempted)&!is.na(f$value)
  candidates$points_attempted[changed]<-f$value[changed]
  candidates$classification_rule[changed]<-f$classification_rule[changed]
  candidates$value_status[changed]<-ifelse(f$classification_rule[changed]%in%c('unique_NBA_event_observation','unique_box_attempt_constraints'),'reconstructed','observed')
  ri<-f$reference_row;good<-!is.na(ri)
  for(pair in list(c('snapshot_id','reference_snapshot_id'),c('source_row','reference_source_row'),c('nba_event_id','reference_event_id'),c('nba_game_id','reference_game_id'),c('nba_player_id','reference_player_id'),c('evidence','identity_evidence')))candidates[[pair[2]]][good]<-reference[[pair[1]]][ri[good]]
  candidates$reference_outcome_checked<-f$reference_outcome_checked
  # No previously rejected identity, duplicate, context or outcome evidence is
  # cleared by the terminal-score fix. Eight exact count checks still apply.
  safe<-all(candidates$reason%in%c('','game_shooting_totals_not_certified','game_contains_unverified_shot_evidence'))
  passed<-safe && nrow(terminal)==1L && terminal$eligible%in%TRUE && nrow(checks)==8L && all(checks$status=='match') && !any(f$conflict) && !anyNA(candidates$points_attempted) && !anyNA(candidates$made)
  candidates$certification_status<-if(passed)'certified' else 'noncertified'
  if(passed)candidates$reason<-''
  candidates$dataset_id<-paste0('shot-recovery:phase4:',id,':',signature)
  checks$season<-candidates$season[1];checks$dataset_id<-candidates$dataset_id[1]
  list(game_id=id,method=method,signature=signature,candidates=candidates,checks=checks,terminal=terminal,passed=passed,filled_values=sum(changed),conflicts=sum(f$conflict))
}
