# Derived working inputs only: canonical/source ordering and starter flags stay
# untouched. Every applied change has an event/player-level evidence receipt.
recovery_projection <- function(e,p) {
  original<-e;f<-event_features(e,p);audit<-list();permutation<-seq_len(nrow(e))
  if('name'%in%names(p)) {
    exact_player<-function(text,team=NULL) {
      variants<-unique(c(trimws(text),sub('[.]$','',trimws(text))))
      ids<-unique(p$player_id[normalize_name(trimws(p$name))%in%normalize_name(variants) & !p$did_not_play%in%TRUE & (is.null(team) | p$team_id%in%team)])
      if(length(ids)==1L)ids else NA_character_
    }
    for(i in which(f$sub & grepl(' enters the game for ',e$description,fixed=TRUE))) {
      names<-strsplit(e$description[i],' enters the game for ',fixed=TRUE)[[1]]
      if(length(names)!=2L || is.na(e$team_id[i]))next
      incoming<-exact_player(names[1],e$team_id[i]);outgoing<-exact_player(names[2],e$team_id[i])
      if(anyNA(c(incoming,outgoing)) || incoming==outgoing)next
      known<-c(e$player_id[i],e$secondary_player_id[i]);known<-known[!is.na(known) & known!='espn:0']
      if(any(!known%in%c(incoming,outgoing)))next
      for(field in c('player_id','secondary_player_id'))if(is.na(e[[field]][i]) || e[[field]][i]=='espn:0' || e[[field]][i]!=if(field=='player_id')incoming else outgoing) {
        prior<-e[[field]][i]
        id<-if(field=='player_id')incoming else outgoing;e[[field]][i]<-id
        audit[[length(audit)+1L]]<-data.frame(game_id=e$game_id[i],event_id=e$event_id[i],player_id=id,rule='exact_roster_name_in_observed_substitution',raw_order=e$event_order[i],derived_order=e$event_order[i],evidence=paste(field,'native:',prior,'derived:',id,e$description[i]))
      }
    }
    for(i in which(f$jump & (is.na(e$tertiary_player_id)|e$tertiary_player_id=='espn:0') & grepl(' gains possession',e$description,fixed=TRUE))) {
      prefix<-sub(' gains possession[.) ]*$','',e$description[i])
      if(identical(prefix,e$description[i]))next
      prefix<-normalize_name(prefix);names<-normalize_name(trimws(p$name))
      matches<-vapply(names,function(name)!is.na(name) && (prefix==name || endsWith(prefix,paste0('(',name)) || endsWith(prefix,paste0('. ',name)) || endsWith(prefix,paste0('-- ',name))),logical(1))
      ids<-unique(p$player_id[matches & !p$did_not_play%in%TRUE])
      if(length(ids)!=1L)next
      e$tertiary_player_id[i]<-ids
      audit[[length(audit)+1L]]<-data.frame(game_id=e$game_id[i],event_id=e$event_id[i],player_id=ids,rule='exact_roster_name_explicit_jump_winner',raw_order=e$event_order[i],derived_order=e$event_order[i],evidence=e$description[i])
    }
  }
  f<-event_features(e,p)
  ordinary<-f$ft & !f$retained & grepl('[123] of [123]',f$type)
  groups<-split(which(ordinary),paste(e$period[ordinary],e$clock[ordinary],e$team_id[ordinary],e$player_id[ordinary]))
  for(ix in groups) {
    ordinal<-as.integer(sub('.*([123]) of [123].*','\\1',f$type[ix]))
    total<-as.integer(sub('.*[123] of ([123]).*','\\1',f$type[ix]))
    if(anyNA(e$player_id[ix]) || length(unique(total))!=1L || length(ix)!=total[1] || !identical(sort(ordinal),seq_len(total[1])))next
    span<-seq.int(min(ix),max(ix));other<-setdiff(span,ix)
    if(any(e$period[span]!=e$period[ix[1]] | e$clock[span]!=e$clock[ix[1]]))next
    if(any((f$fg|f$ft|f$tov|f$dreb|f$oreb|f$jump)[other]))next
    if(any(f$sub[other] & (e$player_id[other]%in%e$player_id[ix] | e$secondary_player_id[other]%in%e$player_id[ix])))next
    if(identical(ordinal,sort(ordinal)))next
    permutation[ix]<-ix[order(ordinal)]
    audit[[length(audit)+1L]]<-data.frame(game_id=e$game_id[ix],event_id=e$event_id[ix],player_id=e$player_id[ix],rule='complete_numbered_same_clock_free_throw_trip',raw_order=e$event_order[ix],derived_order=e$event_order[ix[order(order(ordinal))]],evidence=e$event_type[ix])
  }
  e<-e[permutation,,drop=FALSE];e$event_order<-original$event_order
  f<-event_features(e,p)
  # Missing flags can be replaced in this projection only when first observed
  # participation/exit versus entry uniquely determines all five period starters.
  for(team in unique(p$team_id)) {
    rp<-which(p$team_id==team & !p$did_not_play%in%TRUE)
    if(!length(rp) || !all(is.na(p$starter[rp])))next
    ix<-which(e$period==1L);subs<-ix[f$sub[ix] & e$team_id[ix]%in%team];signals<-ix[f$action[ix]]
    present<-absent<-character()
    for(player in p$player_id[rp]) {
      incoming<-subs[e$player_id[subs]%in%player][1]
      outgoing<-subs[e$secondary_player_id[subs]%in%player][1]
      action<-signals[e$player_id[signals]%in%player | e$secondary_player_id[signals]%in%player | e$tertiary_player_id[signals]%in%player][1]
      ins<-if(is.na(incoming))Inf else incoming;first<-min(c(Inf,outgoing,action),na.rm=TRUE)
      if(is.finite(first) && first<ins)present<-c(present,player)
      if(is.finite(ins) && ins<first)absent<-c(absent,player)
    }
    candidates<-setdiff(p$player_id[rp],absent)
    active<-if(length(present)==5L)present else if(length(candidates)==5L)candidates else character()
    if(length(active)!=5L || length(present)>5L || !all(present%in%active) || any(active%in%absent))next
    p$starter[rp]<-p$player_id[rp]%in%active
    audit[[length(audit)+1L]]<-data.frame(game_id=e$game_id[1],event_id=NA_character_,player_id=active,rule='unique_initial_five_missing_starter_flags',raw_order=NA_integer_,derived_order=NA_integer_,evidence='all source starter flags missing; first participation/exit precedes first entry; exactly five possible players')
  }
  receipt<-if(length(audit))do.call(rbind,audit) else data.frame(game_id=character(),event_id=character(),player_id=character(),rule=character(),raw_order=integer(),derived_order=integer(),evidence=character())
  list(e=e,p=p,audit=receipt)
}

recovery_method <- function() paste0('pl-recovery-v1-',substr(digest::digest(list(reconstruction_version,body(recovery_projection),body(normalize_name)),algo='sha256'),1,12))
