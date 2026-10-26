publish_terminal_shots <- function(con,index='data/processed/phase4/terminal_stage.csv',baseline='data/processed/phase4/baseline.duckdb') {
  rows<-utils::read.csv(index,colClasses=c(game_id='character'));rows<-rows[rows$passed,]
  DBI::dbExecute(con,'CREATE TABLE IF NOT EXISTS phase4_shot_publications (game_id VARCHAR PRIMARY KEY,method VARCHAR,signature VARCHAR,path VARCHAR,sha256 VARCHAR,published_at TIMESTAMP)')
  done<-DBI::dbReadTable(con,'phase4_shot_publications')
  if(nrow(done)) {
    j<-match(rows$game_id,done$game_id);stopifnot(all(is.na(j)|rows$signature==done$signature[j]))
    rows<-rows[is.na(j),]
  }
  if(!nrow(rows))return(c(certified_games=0L,certified_attempts=0L,canonical_added=0L))
  results<-lapply(seq_len(nrow(rows)),function(i){stopifnot(file_sha256(rows$path[i])==rows$sha256[i]);r<-readRDS(rows$path[i]);stopifnot(r$method==phase4_shot_method(),r$passed,all(r$checks$status=='match'),nrow(r$checks)==8L,nrow(r$terminal)==1L,r$terminal$eligible);r})
  candidates<-do.call(rbind,lapply(results,`[[`,'candidates'));checks<-do.call(rbind,lapply(results,`[[`,'checks'))
  DBI::dbWriteTable(con,'_phase4_candidates',candidates,temporary=TRUE,overwrite=TRUE);DBI::dbWriteTable(con,'_phase4_checks',checks,temporary=TRUE,overwrite=TRUE)
  DBI::dbExecute(con,paste0('ATTACH ',DBI::dbQuoteString(con,normalizePath(baseline,winslash='/')),' AS phase3_frozen (READ_ONLY)'));on.exit(DBI::dbExecute(con,'DETACH phase3_frozen'),add=TRUE)
  count<-function(q)as.numeric(DBI::dbGetQuery(con,q)[[1]][1])
  stopifnot(count("SELECT count(*) FROM shot_recovery_candidates WHERE certification_status='certified' AND game_id IN (SELECT game_id FROM _phase4_candidates)")==0)
  stopifnot(count('SELECT count(*) FROM ((SELECT * FROM shot_recovery_candidates WHERE game_id IN (SELECT game_id FROM _phase4_candidates)) EXCEPT (SELECT * FROM phase3_frozen.main.shot_recovery_candidates WHERE game_id IN (SELECT game_id FROM _phase4_candidates)))')==0)
  stopifnot(count('SELECT count(*) FROM ((SELECT * FROM phase3_frozen.main.shot_recovery_candidates WHERE game_id IN (SELECT game_id FROM _phase4_candidates)) EXCEPT (SELECT * FROM shot_recovery_candidates WHERE game_id IN (SELECT game_id FROM _phase4_candidates)))')==0)
  stopifnot(count('SELECT count(*) FROM _phase4_candidates c JOIN shot_attempts s USING(game_id,event_id) WHERE c.player_id IS DISTINCT FROM s.player_id OR c.team_id IS DISTINCT FROM s.team_id OR c.points_attempted IS DISTINCT FROM s.points_attempted OR c.made IS DISTINCT FROM s.made')==0)
  stopifnot(count('SELECT count(*) FROM _phase4_candidates c LEFT JOIN player_box_scores p ON c.game_id=p.game_id AND c.player_id=p.player_id AND c.team_id=p.team_id WHERE p.player_id IS NULL OR p.did_not_play IS TRUE')==0)
  DBI::dbWithTransaction(con,{
    for(table in c('shot_recovery_candidates','shot_recovery_checks')) {
      archive<-paste0('phase4_prior_',table)
      DBI::dbExecute(con,paste0('CREATE TABLE IF NOT EXISTS ',archive,' AS SELECT * FROM ',table,' WHERE FALSE'))
      DBI::dbExecute(con,paste0('INSERT INTO ',archive,' SELECT * FROM ',table,' WHERE game_id IN (SELECT game_id FROM _phase4_candidates)'))
      DBI::dbExecute(con,paste0('DELETE FROM ',table,' WHERE game_id IN (SELECT game_id FROM _phase4_candidates)'))
    }
    DBI::dbExecute(con,'INSERT INTO shot_recovery_candidates BY NAME SELECT * FROM _phase4_candidates');DBI::dbExecute(con,'INSERT INTO shot_recovery_checks BY NAME SELECT * FROM _phase4_checks')
    DBI::dbExecute(con,'CREATE TABLE IF NOT EXISTS phase4_terminal_score_evidence (canonical_game_id VARCHAR,nba_game_id VARCHAR,snapshot_id VARCHAR,source_row BIGINT,event_id VARCHAR,period INTEGER,home_score INTEGER,away_score INTEGER,score_pairs INTEGER,valid_terminal BOOLEAN,eligible BOOLEAN,artifact_dataset_id VARCHAR,PRIMARY KEY(canonical_game_id))')
    for(i in seq_along(results)) {
      r<-results[[i]];c<-r$candidates;id<-r$game_id
      source<-DBI::dbGetQuery(con,'SELECT * FROM datasets WHERE dataset_id=?',params=list(c$source_dataset_id[1]))
      for(kind in c('candidates','checks'))upsert_rows(con,'datasets',data.frame(dataset_id=paste0(c$dataset_id[1],':',kind),source_id=source$source_id,url=source$url,revision=r$method,retrieved_at=Sys.time(),sha256=rows$sha256[i],raw_path=rows$path[i],row_count=if(kind=='candidates')nrow(c) else nrow(r$checks)),'dataset_id')
      parents<-unique(c(c$source_dataset_id,c$canonical_event_dataset_id,c$reference_snapshot_id,DBI::dbGetQuery(con,'SELECT dataset_id FROM team_box_scores WHERE game_id=? UNION SELECT dataset_id FROM player_box_scores WHERE game_id=?',params=list(id,id))$dataset_id,DBI::dbGetQuery(con,'SELECT DISTINCT snapshot_id FROM historical_player_boxes WHERE game_id=?',params=list(r$terminal$game_id))$snapshot_id));parents<-parents[!is.na(parents)]
      for(kind in c('candidates','checks'))upsert_rows(con,'dataset_dependencies',data.frame(dataset_id=paste0(c$dataset_id[1],':',kind),parent_dataset_id=parents,transformation='Observed unique zero-clock Game End score; all original eight NBA shot-count checks and full player-identity gates; unique FG-event linkage; exact canonical four-metric checks'),c('dataset_id','parent_dataset_id'))
      t<-r$terminal
      DBI::dbAppendTable(con,'phase4_terminal_score_evidence',data.frame(canonical_game_id=id,nba_game_id=t$game_id,snapshot_id=t$snapshot_id,source_row=t$source_row,event_id=t$event_id,period=t$period,home_score=t$home_score,away_score=t$away_score,score_pairs=t$score_pairs,valid_terminal=t$valid_terminal,eligible=t$eligible,artifact_dataset_id=paste0(c$dataset_id[1],':checks')))
      DBI::dbAppendTable(con,'phase4_shot_publications',data.frame(game_id=id,method=r$method,signature=r$signature,path=rows$path[i],sha256=rows$sha256[i],published_at=Sys.time()))
    }
    added<-DBI::dbExecute(con,"INSERT INTO shot_attempts SELECT c.game_id,c.event_id,c.player_id,c.team_id,c.points_attempted,c.made,c.x,c.y,c.coordinate_system,CASE WHEN c.value_status='reconstructed' THEN 'reconstructed_unique_constraints' ELSE 'provider_observed' END,c.dataset_id||':candidates' FROM _phase4_candidates c WHERE NOT EXISTS(SELECT 1 FROM shot_attempts s WHERE s.game_id=c.game_id AND s.event_id=c.event_id)")
    gates<-rbind(shot_recovery_integrity(con),terminal_shot_integrity(con))
    if(any(!gates$passed))stop('Terminal shot publication gates failed: ',paste(gates$check[!gates$passed],collapse=', '))
  })
  c(certified_games=nrow(rows),certified_attempts=nrow(candidates),canonical_added=added)
}
