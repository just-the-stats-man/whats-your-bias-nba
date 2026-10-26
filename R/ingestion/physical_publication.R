physical_recovery_inputs <- function(con,id,method=recovery_method()) {
  g<-DBI::dbGetQuery(con,'SELECT * FROM games WHERE game_id=?',params=list(id))
  e<-DBI::dbGetQuery(con,'SELECT * FROM pbp_events WHERE game_id=? ORDER BY event_order',params=list(id))
  p<-DBI::dbGetQuery(con,'SELECT p.*,n.name FROM player_box_scores p JOIN players n USING(player_id) WHERE game_id=? ORDER BY player_id',params=list(id))
  t<-DBI::dbGetQuery(con,'SELECT * FROM team_box_scores WHERE game_id=? ORDER BY team_id',params=list(id))
  refs<-DBI::dbGetQuery(con,'SELECT * FROM reconciliation_checks WHERE game_id=? ORDER BY team_id,metric',params=list(id))
  benchmark<-DBI::dbGetQuery(con,'SELECT DISTINCT r.* FROM independent_team_totals r JOIN reconciliation_checks c ON r.dataset_id=c.reference_dataset_id AND r.source_game_id=c.reference_game_id AND r.team_id=c.team_id WHERE c.game_id=? ORDER BY r.team_id',params=list(id))
  source<-DBI::dbGetQuery(con,'SELECT DISTINCT d.* FROM datasets d WHERE d.dataset_id IN (SELECT dataset_id FROM pbp_events WHERE game_id=?)',params=list(id))
  benchmark$independent<-!benchmark$source_id%in%source$source_id
  list(g=g,e=e,p=p,t=t,refs=refs,benchmark=benchmark,source=source,method=method)
}

publish_physical_recovery <- function(con,index='data/processed/phase3/physical_stage.csv',diagnostics_directory='data/processed/phase3') {
  stage<-utils::read.csv(index,colClasses=c(game_id='character'))
  regressions<-stage[(stage$possessions_before=='reconciled' & !stage$possession_pass) | (stage$lineups_before=='reconciled' & !stage$lineup_pass),]
  dir.create(diagnostics_directory,recursive=TRUE,showWarnings=FALSE)
  utils::write.csv(regressions,file.path(diagnostics_directory,'physical_regressions.csv'),row.names=FALSE)
  # A regression is a publication gate, never a reason to weaken a check.
  if(nrow(regressions))stop('Affected certified components regress; publication held')
  selected<-stage[(stage$possession_pass & stage$possessions_before!='reconciled') | (stage$lineup_pass & stage$lineups_before!='reconciled'),]
  DBI::dbExecute(con,'CREATE TABLE IF NOT EXISTS phase3_prior_reconstruction_status AS SELECT * FROM reconstruction_status WHERE FALSE')
  DBI::dbExecute(con,'CREATE TABLE IF NOT EXISTS phase3_prior_lineup_minute_checks AS SELECT * FROM lineup_minute_checks WHERE FALSE')
  DBI::dbExecute(con,'CREATE TABLE IF NOT EXISTS reconstruction_component_methods (game_id VARCHAR,component VARCHAR,method VARCHAR,input_signature VARCHAR,artifact_dataset_id VARCHAR,PRIMARY KEY(game_id,component))')
  DBI::dbExecute(con,'CREATE TABLE IF NOT EXISTS recovery_transformations (game_id VARCHAR,event_id VARCHAR,player_id VARCHAR,rule VARCHAR,raw_order INTEGER,derived_order INTEGER,evidence VARCHAR,method VARCHAR,artifact_dataset_id VARCHAR)')
  DBI::dbExecute(con,"CREATE OR REPLACE VIEW reconstruction_event_projection AS WITH a AS (SELECT game_id,event_id,max(player_id) FILTER(WHERE rule='exact_roster_name_in_observed_substitution' AND starts_with(evidence,'player_id ')) incoming,max(player_id) FILTER(WHERE rule='exact_roster_name_in_observed_substitution' AND starts_with(evidence,'secondary_player_id ')) outgoing,max(player_id) FILTER(WHERE rule='exact_roster_name_explicit_jump_winner') winner,max(derived_order) FILTER(WHERE rule='complete_numbered_same_clock_free_throw_trip') derived_order FROM recovery_transformations WHERE event_id IS NOT NULL GROUP BY game_id,event_id) SELECT e.*,coalesce(a.incoming,e.player_id) derived_player_id,coalesce(a.outgoing,e.secondary_player_id) derived_secondary_player_id,coalesce(a.winner,e.tertiary_player_id) derived_tertiary_player_id,coalesce(a.derived_order,e.event_order) derived_event_order FROM pbp_events e LEFT JOIN a USING(game_id,event_id)")
  added<-c(possession_games=0L,lineup_games=0L)
  DBI::dbWithTransaction(con,{
    for(i in seq_len(nrow(selected))) {
      s<-selected[i,];stopifnot(file_sha256(s$path)==s$sha256,s$method==recovery_method())
      r<-readRDS(s$path);id<-s$game_id
      old<-DBI::dbGetQuery(con,'SELECT * FROM reconstruction_status WHERE game_id=?',params=list(id))
      po<-s$possession_pass && old$possessions_status!='reconciled';lu<-s$lineup_pass && old$lineups_status!='reconciled'
      if(!po && !lu)next
      g<-DBI::dbGetQuery(con,'SELECT * FROM games WHERE game_id=?',params=list(id))
      e<-DBI::dbGetQuery(con,'SELECT * FROM pbp_events WHERE game_id=? ORDER BY event_order',params=list(id))
      p<-DBI::dbGetQuery(con,'SELECT p.*,n.name FROM player_box_scores p JOIN players n USING(player_id) WHERE game_id=? ORDER BY player_id',params=list(id))
      t<-DBI::dbGetQuery(con,'SELECT * FROM team_box_scores WHERE game_id=? ORDER BY team_id',params=list(id))
      refs<-DBI::dbGetQuery(con,'SELECT * FROM reconciliation_checks WHERE game_id=? ORDER BY team_id,metric',params=list(id))
      benchmark<-DBI::dbGetQuery(con,'SELECT DISTINCT r.* FROM independent_team_totals r JOIN reconciliation_checks c ON r.dataset_id=c.reference_dataset_id AND r.source_game_id=c.reference_game_id AND r.team_id=c.team_id WHERE c.game_id=? ORDER BY r.team_id',params=list(id))
      source<-DBI::dbGetQuery(con,'SELECT DISTINCT d.* FROM datasets d WHERE d.dataset_id IN (SELECT dataset_id FROM pbp_events WHERE game_id=?)',params=list(id))
      benchmark$independent<-!benchmark$source_id%in%source$source_id
      stopifnot(identical(digest::digest(list(g,e,p,t,refs,benchmark,source,r$method),algo='sha256'),r$signature))
      artifact<-paste0('physical-recovery:',id,':',r$signature)
      manifest<-data.frame(dataset_id=artifact,source_id=source$source_id[1],url=source$url[1],revision=r$method,retrieved_at=Sys.time(),sha256=s$sha256,raw_path=s$path,row_count=nrow(r$audit))
      upsert_rows(con,'datasets',manifest,'dataset_id')
      parents<-unique(c(e$dataset_id,p$dataset_id,t$dataset_id,refs$reference_dataset_id,benchmark$dataset_id));parents<-parents[!is.na(parents)]
      upsert_rows(con,'dataset_dependencies',data.frame(dataset_id=artifact,parent_dataset_id=parents,transformation='Derived explicit-name event roles and uniquely numbered same-clock FT order; original source events unchanged; original physical/count/minute gates'),c('dataset_id','parent_dataset_id'))
      DBI::dbAppendTable(con,'phase3_prior_reconstruction_status',old)
      for(component in c('possessions','lineups'))if(!nrow(DBI::dbGetQuery(con,'SELECT 1 FROM reconstruction_component_methods WHERE game_id=? AND component=?',params=list(id,component))))DBI::dbAppendTable(con,'reconstruction_component_methods',data.frame(game_id=id,component=component,method=old$version,input_signature=old$reference_signature,artifact_dataset_id=old$dataset_id))
      if(po) {
        rows<-r$pos$possessions;rows$reconstruction_version<-r$method;rows$dataset_id<-artifact
        DBI::dbAppendTable(con,'possessions',rows);DBI::dbAppendTable(con,'possession_events',r$pos$events)
        if(nrow(r$pos$extra))DBI::dbAppendTable(con,'non_possession_points',r$pos$extra)
        old$possessions_status<-'reconciled';added['possession_games']<-added['possession_games']+1L
      }
      if(lu) {
        rows<-r$lu$lineups;rows$dataset_id<-artifact
        DBI::dbAppendTable(con,'lineups',rows);DBI::dbAppendTable(con,'lineup_players',r$lu$members)
        prior<-DBI::dbGetQuery(con,'SELECT * FROM lineup_minute_checks WHERE game_id=?',params=list(id));DBI::dbAppendTable(con,'phase3_prior_lineup_minute_checks',prior)
        upsert_rows(con,'lineup_minute_checks',r$lu$checks,c('game_id','player_id'))
        old$lineups_status<-'reconciled';old$resolved_team_periods<-r$lu$resolved;old$expected_team_periods<-r$lu$expected;added['lineup_games']<-added['lineup_games']+1L
      }
      for(component in c(if(po)'possessions',if(lu)'lineups'))upsert_rows(con,'reconstruction_component_methods',data.frame(game_id=id,component=component,method=r$method,input_signature=r$signature,artifact_dataset_id=artifact),c('game_id','component'))
      old$version<-r$method;old$updated_at<-Sys.time();upsert_rows(con,'reconstruction_status',old,'game_id')
      if(nrow(r$audit)) {r$audit$method<-r$method;r$audit$artifact_dataset_id<-artifact;DBI::dbAppendTable(con,'recovery_transformations',r$audit)}
    }
  })
  added
}
