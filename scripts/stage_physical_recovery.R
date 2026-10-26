source('scripts/load.R');con<-phase3_snapshot_connection()
dir.create('data/processed/phase3/physical',recursive=TRUE,showWarnings=FALSE)
tryCatch({
  scope<-utils::read.csv('data/processed/phase3/recovery_scope.csv',colClasses=c(game_id='character'))
  args<-commandArgs(trailingOnly=TRUE)
  if(length(args)) {stopifnot(all(args%in%scope$game_id));scope<-scope[scope$game_id%in%args,]}
  method<-recovery_method();summary<-list();hits<-0L
  for(i in seq_len(nrow(scope))) {
    id<-scope$game_id[i]
    g<-DBI::dbGetQuery(con,'SELECT * FROM games WHERE game_id=?',params=list(id))
    e<-DBI::dbGetQuery(con,'SELECT * FROM pbp_events WHERE game_id=? ORDER BY event_order',params=list(id))
    p<-DBI::dbGetQuery(con,'SELECT p.*,n.name FROM player_box_scores p JOIN players n USING(player_id) WHERE game_id=? ORDER BY player_id',params=list(id))
    t<-DBI::dbGetQuery(con,'SELECT * FROM team_box_scores WHERE game_id=? ORDER BY team_id',params=list(id))
    refs<-DBI::dbGetQuery(con,'SELECT * FROM reconciliation_checks WHERE game_id=? ORDER BY team_id,metric',params=list(id))
    benchmark<-DBI::dbGetQuery(con,'SELECT DISTINCT r.* FROM independent_team_totals r JOIN reconciliation_checks c ON r.dataset_id=c.reference_dataset_id AND r.source_game_id=c.reference_game_id AND r.team_id=c.team_id WHERE c.game_id=? ORDER BY r.team_id',params=list(id))
    source<-DBI::dbGetQuery(con,'SELECT DISTINCT d.* FROM datasets d WHERE d.dataset_id IN (SELECT dataset_id FROM pbp_events WHERE game_id=?)',params=list(id))
    benchmark$independent<-!benchmark$source_id%in%source$source_id
    signature<-digest::digest(list(g,e,p,t,refs,benchmark,source,method),algo='sha256')
    path<-file.path('data/processed/phase3/physical',paste0(id,'-',substr(signature,1,16),'.rds'))
    if(file.exists(path)) {r<-readRDS(path);hits<-hits+1L} else {
      a<-recovery_projection(e,p);f<-event_features(a$e,a$p)
      po<-reconstruct_possessions(a$e,g,a$p,f);lu<-reconstruct_lineups(a$e,g,a$p,f)
      common<-reconcile_pbp_box(a$e,t,f,benchmark)
      if(any(refs$passed%in%FALSE))common<-c(common,'independent game-level totals disagree')
      po$issues<-unique(c(po$issues,common));lu$issues<-unique(c(lu$issues,common))
      r<-list(game=g,signature=signature,method=method,pos=po,lu=lu,checks=attr(common,'checks'),audit=a$audit,source=source,refs=refs,benchmark=benchmark)
      saveRDS(r,path)
    }
    summary[[i]]<-data.frame(game_id=id,season=g$season,method=method,signature=signature,path=path,sha256=file_sha256(path),changed=nrow(r$audit)>0,possessions_before=scope$possessions_status[i],lineups_before=scope$lineups_status[i],possession_pass=!length(r$pos$issues),lineup_pass=!length(r$lu$issues),possession_issues=paste(r$pos$issues,collapse='; '),lineup_issues=paste(r$lu$issues,collapse='; '))
    if(i%%25L==0L)message(i,' / ',nrow(scope))
  }
  out<-do.call(rbind,summary)
  index<-'data/processed/phase3/physical_stage.csv'
  if(length(args) && file.exists(index)) {prior<-utils::read.csv(index,colClasses=c(game_id='character'));out<-rbind(prior[!prior$game_id%in%out$game_id,],out)}
  out<-out[order(out$season,out$game_id),];utils::write.csv(out,index,row.names=FALSE)
  cat('Checkpoint hits:',hits,'of',nrow(scope),'requested games\n')
  print(with(out,table(possessions_before,possession_pass)));print(with(out,table(lineups_before,lineup_pass)))
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
