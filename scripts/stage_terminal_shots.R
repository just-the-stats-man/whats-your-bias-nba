source('scripts/load.R');con<-DBI::dbConnect(duckdb::duckdb(),dbdir='data/processed/phase4/baseline.duckdb',read_only=TRUE)
tryCatch({
  DBI::dbExecute(con,'SET threads=4');DBI::dbExecute(con,"SET memory_limit='3GB'")
  scope<-utils::read.csv('docs/phase4/terminal_recovery_scope.csv',colClasses=c(game_id='character'))
  args<-commandArgs(trailingOnly=TRUE);pilot<-length(args)>0L
  if(pilot)scope<-scope[scope$season%in%args,]
  folder<-'data/processed/phase4/terminal_shots';dir.create(folder,recursive=TRUE,showWarnings=FALSE)
  method<-phase4_shot_method();rows<-list();hits<-0L
  for(season in unique(scope$season)) {
    ref_path<-file.path(folder,paste0('references-',season,'-',method,'.rds'))
    if(file.exists(ref_path))refs<-readRDS(ref_path) else {refs<-terminal_shot_references(con,season);saveRDS(refs,ref_path)}
    c<-DBI::dbGetQuery(con,'SELECT * FROM shot_recovery_candidates WHERE season=? ORDER BY game_id,event_order',params=list(season));e<-DBI::dbGetQuery(con,'SELECT e.* FROM pbp_events e JOIN games g USING(game_id) WHERE g.season=? ORDER BY e.game_id,e.event_order',params=list(season));b<-DBI::dbGetQuery(con,'SELECT t.* FROM team_box_scores t JOIN games g USING(game_id) WHERE g.season=? ORDER BY t.game_id,t.team_id',params=list(season))
    for(id in scope$game_id[scope$season==season]) {
      cc<-c[c$game_id==id,];cc<-cc[order(cc$event_order,cc$event_id),,drop=FALSE];ee<-e[e$game_id==id,];bb<-b[b$game_id==id,]
      rr<-refs$reference[refs$reference$game_id==id,,drop=FALSE];rr<-rr[order(rr$snapshot_id,rr$source_row),,drop=FALSE]
      tt<-refs$terminal[refs$terminal$game_id%in%rr$nba_game_id,,drop=FALSE];tt<-tt[order(tt$game_id,tt$snapshot_id,tt$source_row),,drop=FALSE]
      signature<-digest::digest(list(cc,ee,bb,rr,tt,method),algo='sha256')
      path<-file.path(folder,paste0(id,'-',substr(signature,1,16),'.rds'))
      if(file.exists(path)) {r<-readRDS(path);stopifnot(r$signature==signature,r$method==method);hits<-hits+1L} else {
        r<-stage_terminal_shot_game(cc,ee,bb,rr,tt,method);stopifnot(r$signature==signature);saveRDS(r,path)
      }
      rows[[length(rows)+1L]]<-data.frame(game_id=id,season=season,method=method,signature=r$signature,path=path,sha256=file_sha256(path),passed=r$passed,candidates=nrow(r$candidates),filled_values=r$filled_values,remaining_values=sum(is.na(r$candidates$points_attempted)),conflicts=r$conflicts)
    }
    message(season,': ',sum(vapply(rows,function(r)r$passed&&r$season==season,logical(1))),' passing games')
  }
  result<-do.call(rbind,rows);index<-file.path('data/processed/phase4',if(pilot)'terminal_pilot.csv' else 'terminal_stage.csv');utils::write.csv(result,index,row.names=FALSE)
  cat('Checkpoint hits:',hits,'of',nrow(scope),'requested games\n')
  print(aggregate(result[c('candidates','filled_values')],result[c('season','passed')],sum))
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
