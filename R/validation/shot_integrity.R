shot_recovery_integrity <- function(con) {
  queries<-c(
    certified_duplicate_events='SELECT count(*) FROM (SELECT game_id,event_id FROM certified_shot_attempts GROUP BY ALL HAVING count(*)!=1)',
    certified_invalid_attempt="SELECT count(*) FROM certified_shot_attempts WHERE points_attempted NOT IN (2,3) OR points_attempted IS NULL OR made IS NULL OR player_id IS NULL OR team_id IS NULL",
    certified_free_throws="SELECT count(*) FROM certified_shot_attempts c JOIN pbp_events e USING(game_id,event_id) WHERE regexp_matches(lower(e.event_type),'free[ _-]*throw') OR e.shooting_play IS DISTINCT FROM TRUE OR c.made IS DISTINCT FROM e.scoring_play",
    certified_roster_identity='SELECT count(*) FROM certified_shot_attempts c LEFT JOIN player_box_scores p ON c.game_id=p.game_id AND c.player_id=p.player_id AND c.team_id=p.team_id WHERE p.player_id IS NULL OR p.did_not_play IS TRUE',
    certified_native_pointer='SELECT count(*) FROM certified_shot_attempts c LEFT JOIN datasets d ON c.source_dataset_id=d.dataset_id LEFT JOIN datasets n ON c.dataset_id||\':candidates\'=n.dataset_id WHERE c.source_row<1 OR d.dataset_id IS NULL OR n.dataset_id IS NULL',
    certified_eight_shooting_checks="SELECT count(*) FROM (SELECT DISTINCT game_id FROM certified_shot_attempts) g LEFT JOIN (SELECT game_id,count(*) n,bool_and(status='match') ok FROM shot_recovery_checks GROUP BY game_id) c USING(game_id) WHERE n IS DISTINCT FROM 8 OR ok IS DISTINCT FROM TRUE",
    certified_location_evidence="SELECT count(*) FROM certified_shot_attempts WHERE (x IS NOT NULL OR y IS NOT NULL) AND (coordinate_frame_validated IS DISTINCT FROM TRUE OR coordinate_status!='observed' OR x IS NULL OR y IS NULL OR abs(x)>47 OR abs(y)>25)",
    certified_mixed_game_evidence="SELECT count(*) FROM shot_recovery_candidates c WHERE c.certification_status!='certified' AND c.game_id IN (SELECT game_id FROM certified_shot_attempts)",
    certified_reference_pointer="SELECT count(*) FROM certified_shot_attempts WHERE classification_rule='unique_NBA_event_observation' AND (reference_snapshot_id IS NULL OR reference_source_row IS NULL OR reference_event_id IS NULL OR identity_evidence IS NULL)",
    publication_conflict_admitted='SELECT count(*) FROM certified_shot_attempts WHERE game_id IN (SELECT game_id FROM shot_publication_conflicts)')
  # Recompute the four totals from published evidence, not just cached checks.
  for(metric in c('fga','fgm','fg3a','fg3m')) {
    expr<-switch(metric,fga='count(*)',fgm='count(*) FILTER(WHERE made)',fg3a='count(*) FILTER(WHERE points_attempted=3)',fg3m='count(*) FILTER(WHERE points_attempted=3 AND made)')
    queries[paste0('published_',metric)]<-paste0('SELECT count(*) FROM (SELECT game_id,team_id,',expr,' observed FROM certified_shot_attempts GROUP BY game_id,team_id) c JOIN team_box_scores b USING(game_id,team_id) WHERE c.observed IS DISTINCT FROM b.',metric)
  }
  out<-data.frame(check=names(queries),violations=vapply(queries,function(q)as.numeric(DBI::dbGetQuery(con,q)[[1]][1]),numeric(1)));out$passed<-out$violations==0;out
}

phase3_preservation <- function(con) {
  baseline<-readRDS('data/processed/phase3/phase2_baseline.rds')
  out<-lapply(seq_len(nrow(baseline$tables)),function(i){
    b<-baseline$tables[i,];table<-DBI::dbQuoteIdentifier(con,b$table)
    # Publication may add rows; all original rows must still exist exactly.
    q<-paste0('SELECT count(*) FROM (SELECT * FROM read_parquet(',DBI::dbQuoteString(con,normalizePath(b$path,winslash='/')),') EXCEPT SELECT * FROM ',table,')')
    n<-as.numeric(DBI::dbGetQuery(con,q)[[1]][1])
    if(b$table %in% c('reconstruction_status','lineup_minute_checks') && DBI::dbExistsTable(con,paste0('phase3_prior_',b$table))) {
      q<-paste0('SELECT count(*) FROM (SELECT * FROM read_parquet(',DBI::dbQuoteString(con,normalizePath(b$path,winslash='/')),') EXCEPT (SELECT * FROM ',table,' UNION ALL SELECT * FROM phase3_prior_',b$table,'))')
      n<-as.numeric(DBI::dbGetQuery(con,q)[[1]][1])
    }
    data.frame(check=paste0('preserved_',b$table),violations=n,passed=n==0 && file_sha256(b$path)==b$sha256)
  })
  do.call(rbind,out)
}
