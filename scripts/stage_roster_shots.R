source('scripts/load.R');con<-DBI::dbConnect(duckdb::duckdb(),dbdir='data/processed/phase4/baseline.duckdb',read_only=TRUE)
tryCatch({
  DBI::dbExecute(con,'SET threads=4');DBI::dbExecute(con,"SET memory_limit='3GB'")
  frozen_identity<-verify_frozen_phase3_inputs(con)
  folder<-'data/processed/phase4/roster_shots';dir.create(folder,recursive=TRUE,showWarnings=FALSE)
  method<-roster_projection_method();projection_path<-file.path(folder,paste0('player-projection-',method,'.rds'))
  if(file.exists(projection_path))projection<-readRDS(projection_path) else {projection<-prepare_verified_roster_projection(con);saveRDS(projection,projection_path)}
  stopifnot(file_sha256(projection$source$path)==projection$source$sha256)
  install_verified_roster_projection(con,projection);cat('Uniquely recovered NBA player/team rows:',nrow(projection$rows),'\n')
  references<-terminal_shot_references(con,'2021-22')
  c<-DBI::dbGetQuery(con,"SELECT * FROM shot_recovery_candidates WHERE season='2021-22' ORDER BY game_id,event_order");e<-DBI::dbGetQuery(con,"SELECT e.* FROM pbp_events e JOIN games g USING(game_id) WHERE g.season='2021-22' ORDER BY e.game_id,e.event_order");b<-DBI::dbGetQuery(con,"SELECT t.* FROM team_box_scores t JOIN games g USING(game_id) WHERE g.season='2021-22' ORDER BY t.game_id,t.team_id")
  ids<-DBI::dbGetQuery(con,"WITH q AS (SELECT game_id FROM shot_recovery_checks WHERE season='2021-22' AND metric IN ('fga','fgm') GROUP BY game_id HAVING count(*)=4 AND bool_and(status='match')) SELECT c.game_id,count(*) candidates,count(*) FILTER(WHERE points_attempted IS NULL) unknown_values FROM shot_recovery_candidates c JOIN q USING(game_id) WHERE c.season='2021-22' GROUP BY c.game_id HAVING bool_and(certification_status!='certified') AND count(*) FILTER(WHERE points_attempted IS NULL)>0 ORDER BY c.game_id")
  utils::write.csv(ids,'docs/phase4/roster_recovery_scope.csv',row.names=FALSE)
  args<-commandArgs(trailingOnly=TRUE);pilot<-length(args)>0L;if(pilot)ids<-head(ids,as.integer(args[1]))
  result<-list();hits<-0L
  index_path<-'data/processed/phase4/roster_stage.csv';old_index<-if(file.exists(index_path))utils::read.csv(index_path,colClasses=c(game_id='character')) else data.frame()
  cache_path<-file.path(folder,paste0('checkpoint-inputs-',method,'.rds'));cache<-if(file.exists(cache_path))readRDS(cache_path) else list()
  for(id in ids$game_id) {
    cc<-c[c$game_id==id,];cc<-cc[order(cc$event_order,cc$event_id),,drop=FALSE];ee<-e[e$game_id==id,];bb<-b[b$game_id==id,]
    rr<-references$reference[references$reference$game_id==id,,drop=FALSE];rr<-rr[order(rr$snapshot_id,rr$source_row),,drop=FALSE]
    tt<-references$terminal[references$terminal$game_id%in%rr$nba_game_id,,drop=FALSE];tt<-tt[order(tt$game_id,tt$snapshot_id,tt$source_row),,drop=FALSE]
    input_key<-terminal_checkpoint_key(cc,ee,bb,rr,tt,method)
    known<-if(nrow(old_index))old_index[old_index$game_id==id & old_index$method==method,] else data.frame()
    record<-cache[[id]]
    reusable<-!is.null(record)&&identical(record$input_key,input_key)&&identical(record$frozen_identity,frozen_identity)
    migrate<-is.null(record)&&nrow(known)==1L
    if(reusable||migrate) {
      path<-if(reusable)record$path else known$path
      sha<-if(reusable)record$sha256 else known$sha256
      stopifnot(file_sha256(path)==sha);r<-readRDS(path);stopifnot(r$method==method)
      if(migrate)stopifnot(r$signature==known$signature)
      hits<-hits+1L
    } else {
      signature<-digest::digest(list(cc,ee,bb,rr,tt,method),algo='sha256');path<-file.path(folder,paste0(id,'-',substr(signature,1,16),'.rds'))
      r<-stage_terminal_shot_game(cc,ee,bb,rr,tt,method)
      r$player_team_evidence<-projection$evidence[projection$evidence$game_id==id,];r$player_projection_rows<-projection$rows[projection$rows$game_id%in%r$terminal$game_id,]
      stopifnot(r$signature==signature);saveRDS(r,path)
    }
    cache[[id]]<-list(input_key=input_key,frozen_identity=frozen_identity,path=path,sha256=file_sha256(path))
    result[[length(result)+1L]]<-data.frame(game_id=id,season='2021-22',method=method,signature=r$signature,path=path,sha256=file_sha256(path),passed=r$passed,candidates=nrow(r$candidates),filled_values=r$filled_values,remaining_values=sum(is.na(r$candidates$points_attempted)),conflicts=r$conflicts)
    if(length(result)%%100L==0L)message(length(result),' / ',nrow(ids))
  }
  out<-do.call(rbind,result);utils::write.csv(out,paste0('data/processed/phase4/roster_',if(pilot)'pilot' else 'stage','.csv'),row.names=FALSE)
  saveRDS(cache,cache_path)
  cat('Checkpoint hits:',hits,'of',nrow(ids),'requested games\n')
  print(aggregate(out[c('candidates','filled_values')],out['passed'],sum))
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
