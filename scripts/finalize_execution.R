source('scripts/load.R')
con<-connect_warehouse()
tryCatch({
  DBI::dbExecute(con,'SET threads=4');DBI::dbExecute(con,"SET memory_limit='3GB'")
  stopifnot(jsonlite::read_json('data/processed/sdv_reconstruction_run.json')$state=='published')
  # Separate staging jobs can run while the physical reconstruction owns the
  # main database. Publish only their new provider tables and manifest entries.
  for(item in list(list(path='data/processed/tracking_stage.duckdb',tables=c('tracking_provider_context','tracking_provider_estimates')),list(path='data/processed/boxscorelab_stage.duckdb',tables=c('boxscorelab_player_season_totals','boxscorelab_team_standings','boxscorelab_team_game_results')))) {
    DBI::dbExecute(con,paste('ATTACH',DBI::dbQuoteString(con,normalizePath(item$path,winslash='/')),'AS extra (READ_ONLY)'))
    tryCatch(DBI::dbWithTransaction(con,{
      for(t in c('sources','datasets','dataset_dependencies'))DBI::dbExecute(con,paste('INSERT OR IGNORE INTO',t,'SELECT * FROM extra.main.',t))
      for(t in item$tables) {
        DBI::dbExecute(con,paste('CREATE TABLE IF NOT EXISTS',t,'AS SELECT * FROM extra.main.',t,'WHERE FALSE'))
        DBI::dbExecute(con,paste('DELETE FROM',t,'WHERE dataset_id IN (SELECT DISTINCT dataset_id FROM extra.main.',t,')'))
        DBI::dbExecute(con,paste('INSERT INTO',t,'SELECT * FROM extra.main.',t))
      }
    }),finally=DBI::dbExecute(con,'DETACH extra'))
  }
  # Correct cached status metadata without touching any physical inputs.
  DBI::dbExecute(con,"UPDATE sdv_history_status s SET event_status='failed_validation' FROM schedule_inventory i WHERE s.game_id=i.game_id AND i.has_pbp AND s.event_status='source_missing'")
  DBI::dbExecute(con,'UPDATE sdv_history_status s SET shot_rows=(SELECT count(*) FROM shot_attempts a WHERE a.game_id=s.game_id)')
  core<-assert_warehouse_integrity(con);historic<-historical_integrity(con);extra<-execution_integrity(con)
  stopifnot(all(historic$passed),all(extra$passed))
  utils::write.csv(extra,'docs/execution_integrity.csv',row.names=FALSE)
  pending<-DBI::dbGetQuery(con,'SELECT g.game_id FROM games g LEFT JOIN reconstruction_status s ON g.game_id=s.game_id AND s.version=? WHERE s.game_id IS NULL',params=list(reconstruction_version))
  stopifnot(nrow(pending)==0L)
  completeness_report(con,years=1994:2027)
  execution_reports(con);boxscorelab_reports(con)
  utils::write.csv(DBI::dbGetQuery(con,'SELECT season,box_status,event_status,count(*) games,sum(shot_rows) shot_rows,sum(unknown_attempts) unknown_attempts FROM sdv_history_status GROUP BY season,box_status,event_status ORDER BY season,box_status,event_status'),'docs/sdv_history_status.csv',row.names=FALSE)
  counts<-do.call(rbind,lapply(c('games','players','teams','player_box_scores','team_box_scores','pbp_events','shot_attempts','possessions','lineups','lineup_players','matchup_observations','tracking_provider_context','tracking_provider_estimates','boxscorelab_player_season_totals','boxscorelab_team_standings','boxscorelab_team_game_results'),function(t)data.frame(table=t,rows=DBI::dbGetQuery(con,paste('SELECT count(*) n FROM',t))$n)))
  utils::write.csv(counts,'docs/warehouse_counts.csv',row.names=FALSE)
  utils::write.csv(DBI::dbGetQuery(con,'SELECT g.season,c.* FROM reconciliation_checks c JOIN games g USING(game_id) WHERE c.passed IS FALSE ORDER BY g.season,c.game_id,c.team_id,c.metric'),'docs/reference_disagreements.csv',row.names=FALSE)
  manifest<-DBI::dbReadTable(con,'datasets')
  manifest$actual_sha256<-vapply(manifest$raw_path,file_sha256,character(1))
  manifest$hash_matches<-manifest$actual_sha256==manifest$sha256
  utils::write.csv(manifest,'data/processed/reports/manifest_verification.csv',row.names=FALSE)
  stopifnot(all(manifest$hash_matches))
  # Export the expanded canonical snapshot separately from the frozen baseline.
  destination<-'data/processed/execution_parquet';dir.create(destination,recursive=TRUE,showWarnings=FALSE)
  selected<-c('games','players','player_box_scores','team_box_scores','pbp_events','shot_attempts','possessions','possession_events','non_possession_points','lineups','lineup_players','reconstruction_status','reconciliation_checks','pbp_reconciliation_checks','schedule_inventory','sdv_history_status','sdv_history_checkpoints','sdv_nba_player_links','tracking_provider_context','tracking_provider_estimates')
  selected<-c(selected,'sources','datasets','dataset_dependencies','ingestion_runs','teams','team_identities','seasons','player_identifiers','substitutions','quality_exceptions','lineup_minute_checks','independent_team_totals','boxscorelab_player_season_totals','boxscorelab_team_standings','boxscorelab_team_game_results','boxscorelab_reconciliation')
  for(t in selected)DBI::dbExecute(con,paste0('COPY (SELECT * FROM ',t,') TO ',DBI::dbQuoteString(con,normalizePath(file.path(destination,paste0(t,'.parquet')),winslash='/',mustWork=FALSE)),' (FORMAT PARQUET)'))
  print(counts)
  jsonlite::write_json(list(method=reconstruction_version,core_checks=sum(core$passed),historical_checks=sum(historic$passed),execution_checks=sum(extra$passed),manifest_entries=nrow(manifest),distinct_paths=length(unique(manifest$raw_path)),pending_games=nrow(pending),raw_hashes_passed=all(manifest$hash_matches),counts=counts,verified_at=format(Sys.time(),tz='UTC',usetz=TRUE)),'data/processed/phase2/final_execution_verification.json',auto_unbox=TRUE,pretty=TRUE)
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
