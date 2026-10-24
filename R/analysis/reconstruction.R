# Reconstructed observations, never primary-defender assignments.
records_frame <- function(records,template) {
  if(!length(records)) return(as.data.frame(lapply(template,function(x)x[FALSE]),stringsAsFactors=FALSE))
  out<-lapply(names(template),function(k)unlist(lapply(records,function(r)r[[k]]),use.names=FALSE))
  names(out)<-names(template);as.data.frame(out,stringsAsFactors=FALSE)
}

event_features <- function(e,roster) {
  type<-tolower(e$event_type);text<-tolower(e$description)
  ft<-grepl('free throw',type)
  retained<-ft & grepl('technical|flagrant|clear path|away from',type)
  key<-paste(e$period,e$clock)
  retained_foul<-grepl('flagrant|clear path|transition take foul|away from play',type) & !ft
  retained<-retained | (ft & key%in%key[retained_foul])
  fg<-e$shooting_play%in%TRUE & !ft
  made<-e$scoring_play%in%TRUE
  tov<-grepl('turnover|traveling|double dribble|palming|carrying',type)
  finalft<-ft & grepl('([123]) of \\1',type,perl=TRUE)
  dreb<-grepl('defensive rebound',type)
  oreb<-grepl('offensive rebound',type)
  jump<-grepl('jumpball|jump ball',type)
  deadball<-rep(FALSE,nrow(e))
  for(i in which(dreb|oreb)) {
    before<-which(seq_len(nrow(e))<i & e$period==e$period[i] & (fg|ft|tov|dreb|oreb))
    after<-which(seq_len(nrow(e))>i & e$period==e$period[i] & (fg|ft|tov|dreb|oreb))
    prev<-tail(before,1);next_event<-head(after,1)
    if(length(prev) && length(next_event))deadball[i]<-ft[prev] && !finalft[prev] && !made[prev] && ft[next_event] && !retained[prev] && !retained[next_event] && e$clock[prev]==e$clock[i] && e$clock[next_event]==e$clock[i]
  }
  points<-ifelse(made,as.integer(e$score_value),0L)
  value<-as.integer(e$points_attempted)
  # Historical FG value comes from an explicit provider description, never a
  # location model. Missing shot-value annotations do not create coordinates.
  value[fg & is.na(value)]<-ifelse(grepl('three point|3-point|3 point',text[fg & is.na(value)]),3L,2L)
  action<-(fg|ft|tov|dreb|oreb|jump|grepl('personal foul|shooting foul|loose ball foul|offensive foul|offensive charge|goaltend|kicked ball|blocking foul',type)) & !grepl('technical|flagrant|ejection',type)
  clock<-strsplit(as.character(e$clock),':',fixed=TRUE)
  remain<-vapply(clock,function(x)if(length(x)==2L)as.numeric(x[1])*60+as.numeric(x[2]) else NA_real_,numeric(1))
  length_sec<-ifelse(e$period<=4L,720,300)
  elapsed<-length_sec-remain
  list(type=type,ft=ft,retained=retained,fg=fg,made=made,tov=tov,finalft=finalft,dreb=dreb,oreb=oreb,deadball=deadball,jump=jump,points=points,value=value,action=action,elapsed=elapsed,sub=grepl('substitution',type),end_period=grepl('end period|end of.*quarter|end of.*period',type))
}

reconstruct_possessions <- function(e,game,roster,features=event_features(e,roster)) {
  f<-features;n<-nrow(e);team<-e$team_id
  teams<-c(game$home_team_id,game$away_team_id)
  other<-function(t)teams[teams!=t][1]
  issues<-character();add<-function(x)issues<<-unique(c(issues,x))
  pos<-list();extra<-list();notes<-character();assigned<-rep(NA_character_,n);attr<-rep('administrative',n)
  if(anyNA(f$points))add('missing scoring value')
  if(any(f$ft & !f$retained & !grepl('[123] of [123]',f$type)))add('unrecognized ordinary free-throw sequence')
  if(any(f$points<0 | f$points>3,na.rm=TRUE))add('invalid scoring value')
  if(anyNA(f$elapsed) || any(f$elapsed<0))add('invalid clock')
  if(!identical(sort(unique(e$period)),seq_len(max(e$period))) || max(e$period)<4)add('missing periods')
  total_expected<-c(game$home_score,game$away_score)
  for(k in seq_along(teams)) if(sum(f$points[team%in%teams[k]],na.rm=TRUE)!=total_expected[k])add('PBP scoring does not equal final score')
  if(any(f$points>0 & !team%in%teams,na.rm=TRUE))add('unknown scoring team')
  for(period in sort(unique(e$period))) {
    ix<-which(e$period==period);start<-ix[1];current<-NA_character_;start_seconds<-0
    if(any(diff(f$elapsed[ix])<0,na.rm=TRUE))add('nonmonotonic period clock')
    if(!any(f$end_period[ix] & f$elapsed[ix]==ifelse(period<=4,720,300),na.rm=TRUE))add('missing zero-clock end-period event')
    close<-function(i,reason) {
      if(is.na(current))return(invisible(NULL))
      id<-paste0(game$game_id,':p:',length(pos)+1L)
      range<-seq.int(start,i)
      scoring<-range[f$points[range]>0 & !f$retained[range]]
      if(any(!team[scoring]%in%current))add('opponent points inside possession')
      points<-sum(f$points[scoring],na.rm=TRUE)
      pos[[length(pos)+1L]]<<-list(possession_id=id,game_id=game$game_id,period=as.integer(period),offense_team_id=current,start_event_id=e$event_id[start],end_event_id=e$event_id[i],start_order=e$event_order[start],end_order=e$event_order[i],points=as.integer(points),end_reason=reason,reconstruction_version=reconstruction_version,dataset_id=e$dataset_id[i],start_seconds=as.numeric(start_seconds),end_seconds=as.numeric(f$elapsed[i]),duration_seconds=as.numeric(f$elapsed[i]-start_seconds))
      regular<-range[!f$retained[range] & !f$jump[range]];assigned[regular]<<-id;attr[regular]<<-'possession'
      current<<-NA_character_;start<<-i+1L;start_seconds<<-f$elapsed[i]
    }
    for(i in ix) {
      if(f$retained[i]) {
        attr[i]<-'retained_or_technical_free_throw'
        if(f$points[i]>0)extra[[length(extra)+1L]]<-list(game_id=game$game_id,event_id=e$event_id[i],team_id=team[i],points=as.integer(f$points[i]),reason='technical_or_retained_possession_free_throw')
        next
      }
      hint<-NA_character_
      if(f$fg[i] || (f$ft[i] && !f$retained[i]) || f$tov[i] || (f$oreb[i] && !f$deadball[i]))hint<-team[i]
      if(f$dreb[i] && !f$deadball[i] && team[i]%in%teams)hint<-other(team[i])
      if(!is.na(hint) && !hint%in%teams){add('unknown team on ball-control event');hint<-NA_character_}
      if(is.na(current) && !is.na(hint))current<-hint
      if(!is.na(current) && !is.na(hint) && hint!=current)add(paste('unexplained change of offensive control',e$event_id[i],current,'->',hint,e$event_type[i]))
      if(f$jump[i]) {
        attr[i]<-'neutral_control_event'
        winner<-roster$team_id[match(e$tertiary_player_id[i],roster$player_id)]
        if(length(winner) && !is.na(winner)) {
          j<-i+1L
          paired_turnover<-j%in%ix && f$tov[j] && e$clock[j]==e$clock[i] && team[j]%in%teams && team[j]!=winner && e$secondary_player_id[j]%in%c(e$player_id[i],e$secondary_player_id[i])
          if(paired_turnover) {
            # Provider order can put the jump before the same-clock turnover
            # that caused it. Keep raw order; apply the lost-ball control state
            # before awarding the jump. Never count a second control change.
            notes<-c(notes,paste('same-clock jump/turnover causal dependency',e$event_id[i],e$event_id[j]))
            if(is.na(current))current<-team[j] else if(current!=team[j])add('inconsistent jump/turnover causal dependency')
          } else {
            if(!is.na(current) && current!=winner)close(i,'jump_ball_change')
            if(is.na(current) && start<=i)current<-winner
          }
        } else if(i>ix[1]+2L) add('unresolved held jump ball')
      }
      if(f$fg[i] && f$made[i]) {
        # A made basket plus its same-clock ordinary 1-of-1 FT is one
        # possession. Technical/retained FTs are explicitly outside this sum.
        ahead<-ix[ix>i & e$clock[ix]==e$clock[i]]
        continuation<-FALSE
        for(j in ahead) {
          if(f$ft[j] && !f$retained[j]) {continuation<-team[j]%in%team[i] && grepl('1 of 1',f$type[j]);break}
          if(f$fg[j] || f$tov[j] || f$dreb[j] || f$oreb[j] || f$jump[j])break
        }
        if(!continuation)close(i,'made_field_goal')
      } else if(f$ft[i] && f$finalft[i] && f$made[i]) {
        close(i,'made_final_free_throw')
      } else if(f$tov[i]) {
        close(i,'turnover')
      } else if(f$dreb[i] && !f$deadball[i]) {
        # A team/dead-ball rebound between attempts in one free-throw trip
        # does not transfer control. Other unassigned team rebounds require
        # the next ball event to confirm the change.
        ahead<-ix[ix>i]
        next_ball<-ahead[(f$fg|f$ft|f$tov|f$oreb|f$dreb)[ahead] & !f$retained[ahead]][1]
        if(is.na(e$player_id[i]) && !is.na(next_ball) && team[next_ball]%in%current) {
          add(paste('ambiguous team defensive rebound',e$event_id[i]))
        } else close(i,'defensive_rebound')
      }
      if(f$end_period[i])close(i,'period_end')
    }
    if(!is.na(current))add('unclosed period possession')
  }
  pf<-records_frame(pos,list(possession_id='',game_id='',period=0L,offense_team_id='',start_event_id='',end_event_id='',start_order=0L,end_order=0L,points=0L,end_reason='',reconstruction_version='',dataset_id='',start_seconds=0,end_seconds=0,duration_seconds=0))
  ef<-records_frame(extra,list(game_id='',event_id='',team_id='',points=0L,reason=''))
  if(nrow(pf))for(k in seq_along(teams)) {
    scored<-sum(pf$points[pf$offense_team_id==teams[k]])+sum(ef$points[ef$team_id==teams[k]])
    if(scored!=total_expected[k])add('possession plus non-possession points fail final score reconciliation')
  }
  if(any((f$fg | (f$ft & !f$retained) | f$tov) & is.na(assigned)))add('unassigned offensive event')
  counts<-table(factor(pf$offense_team_id,levels=teams))
  if(abs(diff(as.integer(counts)))>max(e$period))add('implausible possession count imbalance')
  list(possessions=pf,events=data.frame(game_id=e$game_id,event_id=e$event_id,possession_id=assigned,attribution=attr),extra=ef,issues=issues,notes=unique(notes))
}

reconstruct_lineups <- function(e,game,roster,features=event_features(e,roster)) {
  f<-features;issues<-character();add<-function(x)issues<<-unique(c(issues,x))
  if(any((f$fg|f$ft) & (is.na(e$player_id) | !e$player_id%in%roster$player_id)))add('missing or unrostered shooter identity')
  participants<-unique(c(e$player_id[f$action],e$secondary_player_id[f$action],e$tertiary_player_id[f$action]))
  participants<-participants[!is.na(participants) & participants!='espn:0']
  if(any(!participants%in%roster$player_id))add('unrostered live-event participant')
  rows<-list();members<-list();resolved<-0L
  played<-setNames(rep(0,nrow(roster)),roster$player_id)
  for(period in sort(unique(e$period)))for(team in c(game$home_team_id,game$away_team_id)) {
    ix<-which(e$period==period);period_seconds<-if(period<=4)720 else 300
    rp<-roster[roster$team_id==team & !roster$did_not_play%in%TRUE,,drop=FALSE]
    ids<-unique(rp$player_id);subs<-ix[f$sub[ix] & e$team_id[ix]%in%team]
    present<-character();absent<-character()
    signals<-ix[f$action[ix]]
    for(player in ids) {
      incoming<-subs[e$player_id[subs]%in%player][1]
      outgoing<-subs[e$secondary_player_id[subs]%in%player][1]
      action<-signals[e$player_id[signals]%in%player | e$secondary_player_id[signals]%in%player | e$tertiary_player_id[signals]%in%player][1]
      ins<-if(is.na(incoming))Inf else incoming
      first<-min(c(Inf,outgoing,action),na.rm=TRUE)
      if(is.finite(first) && first<ins)present<-c(present,player)
      if(is.finite(ins) && ins<first)absent<-c(absent,player)
    }
    if(period==1L) {
      active<-rp$player_id[rp$starter%in%TRUE]
      if(length(active)!=5L || !all(present%in%active) || any(active%in%absent)) {add(paste('period',period,team,'inconsistent starting five'));next}
    } else {
      candidates<-setdiff(ids,absent)
      active<-if(length(present)==5L)present else if(length(candidates)==5L)candidates else character()
      if(length(active)!=5L || length(present)>5L) {add(paste('period',period,team,'ambiguous initial five'));next}
    }
    if(anyNA(f$elapsed[ix]) || any(diff(f$elapsed[ix])<0) || !any(f$end_period[ix] & f$elapsed[ix]==period_seconds)) {add(paste('period',period,'invalid clock coverage'));next}
    local_rows<-list();local_members<-list();local_played<-played*0
    begin<-0;begin_order<-ix[1];ok<-TRUE
    emit<-function(end,ending) {
      if(end>begin) {
        id<-paste(game$game_id,'l',team,period,length(local_rows)+1L,sep=':')
        local_rows[[length(local_rows)+1L]]<<-list(lineup_id=id,game_id=game$game_id,team_id=team,start_event_id=e$event_id[begin_order],end_event_id=e$event_id[ending],observation_type='reconstructed_unique_constraints',dataset_id=e$dataset_id[ending],period=as.integer(period),start_seconds=as.numeric(begin),end_seconds=as.numeric(end),duration_seconds=as.numeric(end-begin))
        for(player in active)local_members[[length(local_members)+1L]]<<-list(lineup_id=id,player_id=player)
        local_played[active]<<-local_played[active]+end-begin
      }
    }
    # Check the actual on-court event participants within every constant-five
    # interval, including secondary assisters/stealers/blockers.
    check_interval<-function(from,to) {
      if(to<from)return(TRUE)
      sig<-seq.int(from,to);sig<-sig[f$action[sig]]
      people<-unique(c(e$player_id[sig],e$secondary_player_id[sig],e$tertiary_player_id[sig]))
      people<-people[people%in%roster$player_id[roster$team_id==team]]
      all(people%in%active)
    }
    for(j in subs) {
      if(!check_interval(begin_order,j-1L)) {ok<-FALSE;add(paste('period',period,team,'event participant absent from five'));break}
      in_id<-e$player_id[j];out_id<-e$secondary_player_id[j]
      if(!in_id%in%ids || !out_id%in%active || in_id%in%active || in_id==out_id) {ok<-FALSE;add(paste('period',period,team,'unresolvable substitution',e$event_id[j]));break}
      emit(f$elapsed[j],j)
      active<-c(setdiff(active,out_id),in_id)
      begin<-f$elapsed[j];begin_order<-j+1L
    }
    if(ok && !check_interval(begin_order,tail(ix,1))) {ok<-FALSE;add(paste('period',period,team,'event participant absent from five'))}
    if(ok) {
      emit(period_seconds,tail(ix,1));resolved<-resolved+1L
      rows<-c(rows,local_rows);members<-c(members,local_members);played<-played+local_played
    }
  }
  tolerance<-ifelse(roster$did_not_play%in%TRUE,0,ifelse(!is.na(roster$minutes) & abs(roster$minutes-round(roster$minutes))<1e-8,60,1.01))
  box<-ifelse(roster$did_not_play%in%TRUE,0,roster$minutes*60)
  checks<-data.frame(game_id=game$game_id,player_id=roster$player_id,reconstructed_seconds=as.numeric(played[roster$player_id]),box_seconds=box,tolerance_seconds=tolerance,passed=!is.na(box) & abs(as.numeric(played[roster$player_id])-box)<=tolerance)
  if(any(!checks$passed))add('reconstructed player minutes exceed source precision bounds')
  lf<-records_frame(rows,list(lineup_id='',game_id='',team_id='',start_event_id='',end_event_id='',observation_type='',dataset_id='',period=0L,start_seconds=0,end_seconds=0,duration_seconds=0))
  mf<-records_frame(members,list(lineup_id='',player_id=''))
  if(nrow(lf)) {
    if(any(table(mf$lineup_id)!=5L) || anyDuplicated(mf))add('lineup does not contain exactly five unique players')
    expected<-sum(ifelse(sort(unique(e$period))<=4,720,300))
    for(team in c(game$home_team_id,game$away_team_id))if(sum(lf$duration_seconds[lf$team_id==team])!=expected)add('lineup intervals fail complete game-time coverage')
  }
  list(lineups=lf,members=mf,checks=checks,issues=issues,resolved=resolved,expected=2L*max(e$period))
}

reconcile_pbp_box <- function(e,box,features) {
  f<-features;issues<-character()
  for(i in seq_len(nrow(box))) {
    team<-box$team_id[i];sel<-e$team_id%in%team
    observed<-c(points=sum(f$points[sel],na.rm=TRUE),fgm=sum(sel & f$fg & f$made),fga=sum(sel & f$fg),fg3m=sum(sel & f$fg & f$made & f$value%in%3),fg3a=sum(sel & f$fg & f$value%in%3),ftm=sum(sel & f$ft & f$made),fta=sum(sel & f$ft),total_turnovers=sum(sel & f$tov))
    for(metric in names(observed))if(!is.na(box[[metric]][i]) && observed[[metric]]!=box[[metric]][i])issues<-c(issues,paste('PBP/box',team,metric,observed[[metric]],'!=',box[[metric]][i]))
  }
  unique(issues)
}
