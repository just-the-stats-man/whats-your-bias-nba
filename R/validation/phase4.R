phase4_preservation <- function(con,baseline='data/processed/phase4/baseline.duckdb') {
  DBI::dbExecute(con,paste0('ATTACH ',DBI::dbQuoteString(con,normalizePath(baseline,winslash='/')),' AS phase3_frozen (READ_ONLY)'));on.exit(DBI::dbExecute(con,'DETACH phase3_frozen'),add=TRUE)
  tables<-utils::read.csv('data/processed/phase4/baseline_tables.csv')$table
  out<-do.call(rbind,lapply(tables,function(table){
    current<-paste0('SELECT * FROM main.',DBI::dbQuoteIdentifier(con,table));archive<-paste0('phase4_prior_',table)
    if(DBI::dbExistsTable(con,archive))current<-paste0(current,' UNION ALL SELECT * FROM ',archive)
    n<-as.numeric(DBI::dbGetQuery(con,paste0('SELECT count(*) FROM (SELECT * FROM phase3_frozen.main.',DBI::dbQuoteIdentifier(con,table),' EXCEPT (',current,'))'))[[1]][1])
    data.frame(check=paste0('phase3_preserved_',table),violations=n,passed=n==0)
  }))
  n<-as.numeric(DBI::dbGetQuery(con,'SELECT count(*) FROM (SELECT * FROM phase3_frozen.main.certified_shot_attempts EXCEPT SELECT * FROM certified_shot_attempts)')[[1]][1])
  rbind(out,data.frame(check='phase3_certified_shots_preserved',violations=n,passed=n==0))
}

terminal_shot_integrity <- function(con) {
  queries<-c(
    terminal_raw_pointer="SELECT count(*) FROM phase4_terminal_score_evidence t LEFT JOIN historical_events e ON t.snapshot_id=e.snapshot_id AND t.source_row=e.source_row WHERE e.event_id IS DISTINCT FROM t.event_id OR e.game_id IS DISTINCT FROM t.nba_game_id OR e.period IS DISTINCT FROM t.period OR NOT regexp_full_match(e.clock,'(PT00M00([.]0+)?S|0:00|00:00)') OR lower(trim(e.event_type))!='game' OR lower(trim(e.description))!='game end' OR e.home_score IS DISTINCT FROM t.home_score OR e.away_score IS DISTINCT FROM t.away_score",
    terminal_eligibility="SELECT count(*) FROM phase4_terminal_score_evidence WHERE eligible IS DISTINCT FROM TRUE OR valid_terminal IS DISTINCT FROM TRUE OR score_pairs!=1",
    terminal_shooting_gates="SELECT count(*) FROM phase4_terminal_score_evidence t LEFT JOIN (SELECT game_id,count(*) n,bool_and(status='reconstructed') ok FROM historical_event_checks WHERE metric!='points' GROUP BY game_id) q ON t.nba_game_id=q.game_id WHERE n IS DISTINCT FROM 8 OR ok IS DISTINCT FROM TRUE",
    terminal_artifact_missing='SELECT count(*) FROM phase4_terminal_score_evidence t LEFT JOIN datasets d ON t.artifact_dataset_id=d.dataset_id WHERE d.dataset_id IS NULL',
    terminal_game_scores='SELECT count(*) FROM phase4_terminal_score_evidence t LEFT JOIN historical_games g ON t.nba_game_id=g.game_id WHERE t.home_score IS DISTINCT FROM g.home_score OR t.away_score IS DISTINCT FROM g.away_score',
    terminal_team_scores="SELECT count(*) FROM phase4_terminal_score_evidence t JOIN historical_games g ON t.nba_game_id=g.game_id LEFT JOIN historical_team_boxes b ON t.nba_game_id=b.game_id AND b.team_id IN (g.home_team_id,g.away_team_id) WHERE b.game_id IS NULL OR b.validation_status!='observed' OR b.points_status!='observed' OR b.points IS DISTINCT FROM CASE WHEN b.team_id=g.home_team_id THEN t.home_score ELSE t.away_score END",
    terminal_game_link='SELECT count(*) FROM phase4_terminal_score_evidence t WHERE NOT EXISTS(SELECT 1 FROM historical_game_links l WHERE l.nba_game_id=t.nba_game_id AND l.espn_game_id=t.canonical_game_id)',
    terminal_certified_game_missing="SELECT count(*) FROM phase4_shot_publications p WHERE NOT EXISTS(SELECT 1 FROM certified_shot_attempts c WHERE c.game_id=p.game_id)")
  out<-data.frame(check=names(queries),violations=vapply(queries,function(q)as.numeric(DBI::dbGetQuery(con,q)[[1]][1]),numeric(1)));out$passed<-out$violations==0;out
}
