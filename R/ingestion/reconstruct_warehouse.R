reconstruct_season <- function(con,season,force=FALSE,batch_size=50L) {
  games<-DBI::dbGetQuery(con,'SELECT * FROM games WHERE season=? ORDER BY game_date,game_id',params=list(season))
  done<-DBI::dbGetQuery(con,'SELECT game_id,dataset_id,reference_signature FROM reconstruction_status WHERE season=? AND version=?',params=list(season,reconstruction_version))
  events<-DBI::dbGetQuery(con,'SELECT e.* FROM pbp_events e JOIN games g USING(game_id) WHERE g.season=? ORDER BY e.game_id,e.event_order',params=list(season))
  boxes<-DBI::dbGetQuery(con,'SELECT p.* FROM player_box_scores p JOIN games g USING(game_id) WHERE g.season=?',params=list(season))
  teams<-DBI::dbGetQuery(con,'SELECT t.* FROM team_box_scores t JOIN games g USING(game_id) WHERE g.season=?',params=list(season))
  independent_failures<-DBI::dbGetQuery(con,'SELECT DISTINCT game_id FROM reconciliation_checks WHERE passed IS DISTINCT FROM TRUE')$game_id
  reference<-DBI::dbGetQuery(con,'SELECT c.* FROM reconciliation_checks c JOIN games g USING(game_id) WHERE g.season=? ORDER BY c.game_id,c.team_id,c.metric',params=list(season))
  signatures<-lapply(split(reference,reference$game_id),function(d)digest::digest(d,algo='sha256'))
  ei<-split(seq_len(nrow(events)),events$game_id);pi<-split(seq_len(nrow(boxes)),boxes$game_id);ti<-split(seq_len(nrow(teams)),teams$game_id)
  for(batch in split(seq_len(nrow(games)),ceiling(seq_len(nrow(games))/batch_size))) {
    results<-list()
    for(i in batch) {
      g<-games[i,,drop=FALSE];id<-g$game_id;e<-events[ei[[id]],,drop=FALSE];p<-boxes[pi[[id]],,drop=FALSE];t<-teams[ti[[id]],,drop=FALSE]
      signature<-if(is.null(signatures[[id]])) 'unavailable' else signatures[[id]]
      if(!force && id%in%done$game_id && identical(done$dataset_id[match(id,done$game_id)],e$dataset_id[1]) && identical(done$reference_signature[match(id,done$game_id)],signature))next
      result<-tryCatch({
        f<-event_features(e,p)
        pos<-reconstruct_possessions(e,g,p,f);lu<-reconstruct_lineups(e,g,p,f)
        common<-reconcile_pbp_box(e,t,f)
        checks<-attr(common,'checks')
        if(id%in%independent_failures)common<-c(common,'independent game-level totals disagree')
        pos$issues<-unique(c(pos$issues,common))
        # Lineup reconciliation must also account for every FG/FT/TOV in the
        # box feed: five consistent names alone are insufficient evidence.
        lu$issues<-unique(c(lu$issues,common))
        list(pos=pos,lu=lu,checks=checks,error=NULL)
      },error=function(err)list(error=conditionMessage(err)))
      if(!is.null(result$error)) {
        result$pos<-list(issues=paste('parser failure:',result$error));result$lu<-list(issues=paste('parser failure:',result$error),resolved=0L,expected=2L*max(e$period))
      }
      result$id<-id;result$game<-g;result$dataset_id<-e$dataset_id[1];result$reference_signature<-signature
      results[[length(results)+1L]]<-result
    }
    if(!length(results))next
    DBI::dbWithTransaction(con,{
      ids<-vapply(results,function(r)r$id,character(1))
      DBI::dbWriteTable(con,'_reconstruct_games',data.frame(game_id=ids),temporary=TRUE,overwrite=TRUE)
      DBI::dbExecute(con,'DELETE FROM lineup_players WHERE lineup_id IN (SELECT lineup_id FROM lineups WHERE game_id IN (SELECT game_id FROM _reconstruct_games))')
      for(table in c('lineups','possessions','possession_events','non_possession_points','lineup_minute_checks','reconstruction_status','pbp_reconciliation_checks'))DBI::dbExecute(con,paste('DELETE FROM',table,'WHERE game_id IN (SELECT game_id FROM _reconstruct_games)'))
      output<-list()
      queue<-function(table,rows) {
        if(nrow(rows))output[[table]][[length(output[[table]])+1L]]<<-rows
      }
      for(r in results) {
        po_ok<-!length(r$pos$issues);lu_ok<-!length(r$lu$issues)
        if(!is.null(r$checks)) {
          queue('pbp_reconciliation_checks',r$checks)
          unavailable<-r$checks[r$checks$status=='unavailable',,drop=FALSE]
          if(nrow(unavailable))queue('quality_exceptions',exception_rows(r$id,season,'pbp_metric','unavailable_attempt_classification',paste(unavailable$team_id,unavailable$metric,'unknown events',unavailable$unknown_events),severity='warning',dataset_id=r$dataset_id))
        }
        if(po_ok) {
          queue('possessions',r$pos$possessions)
          queue('possession_events',r$pos$events)
          queue('non_possession_points',r$pos$extra)
        }
        if(lu_ok) {
          queue('lineups',r$lu$lineups)
          queue('lineup_players',r$lu$members)
        }
        if(!is.null(r$lu$checks))queue('lineup_minute_checks',r$lu$checks)
        if(!po_ok)queue('quality_exceptions',exception_rows(r$id,season,'possessions',r$pos$issues,r$pos$issues,dataset_id=r$dataset_id))
        if(length(r$pos$notes))queue('quality_exceptions',exception_rows(r$id,season,'possessions','causal_dependency',r$pos$notes,severity='warning',dataset_id=r$dataset_id))
        if(!lu_ok)queue('quality_exceptions',exception_rows(r$id,season,'lineups',r$lu$issues,r$lu$issues,dataset_id=r$dataset_id))
        status<-data.frame(game_id=r$id,season=season,version=reconstruction_version,possessions_status=if(po_ok)'reconciled' else 'unresolved',lineups_status=if(lu_ok)'reconciled' else 'unresolved',resolved_team_periods=as.integer(r$lu$resolved),expected_team_periods=as.integer(r$lu$expected),updated_at=Sys.time(),dataset_id=r$dataset_id,reference_signature=r$reference_signature)
        queue('reconstruction_status',status)
      }
      keys<-list(possessions='possession_id',possession_events=c('game_id','event_id'),non_possession_points=c('game_id','event_id'),lineups='lineup_id',lineup_players=c('lineup_id','player_id'),lineup_minute_checks=c('game_id','player_id'),quality_exceptions='exception_id',reconstruction_status='game_id',pbp_reconciliation_checks=c('game_id','team_id','metric'))
      for(table in names(output))upsert_rows(con,table,do.call(rbind,output[[table]]),keys[[table]])
      DBI::dbRemoveTable(con,'_reconstruct_games')
    })
    message(season,': reconstructed through ',max(batch),' / ',nrow(games),' games')
  }
  invisible(NULL)
}
