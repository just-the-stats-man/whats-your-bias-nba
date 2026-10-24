source('scripts/load.R')
con<-connect_warehouse()
tryCatch({
  withdraw_quarantined(con)
  findings<-quarantine_inconsistent_player_totals(con)
  stopifnot(nrow(findings)==0L)
  integrity<-assert_warehouse_integrity(con)
  completeness_report(con)
  utils::write.csv(integrity,'docs/warehouse_integrity.csv',row.names=FALSE)
  counts<-do.call(rbind,lapply(c('games','players','teams','player_box_scores','team_box_scores','pbp_events','possessions','lineups','lineup_players','matchup_observations'),function(table)data.frame(table=table,rows=DBI::dbGetQuery(con,paste('SELECT count(*) n FROM',table))$n)))
  utils::write.csv(counts,'docs/warehouse_counts.csv',row.names=FALSE)
  pending<-DBI::dbGetQuery(con,'SELECT g.game_id FROM games g LEFT JOIN reconstruction_status s ON g.game_id=s.game_id AND s.version=? WHERE s.game_id IS NULL',params=list(reconstruction_version))
  stopifnot(nrow(pending)==0L)
  manifest<-DBI::dbReadTable(con,'datasets')
  manifest$exists<-file.exists(manifest$raw_path)
  manifest$actual_sha256<-vapply(seq_len(nrow(manifest)),function(i)if(manifest$exists[i])file_sha256(manifest$raw_path[i]) else NA_character_,character(1))
  manifest$hash_matches<-manifest$exists & !is.na(manifest$actual_sha256) & manifest$sha256==manifest$actual_sha256
  dir.create('data/processed/reports',recursive=TRUE,showWarnings=FALSE)
  utils::write.csv(manifest,'data/processed/reports/manifest_verification.csv',row.names=FALSE)
  cat('Manifest checks:',sum(manifest$hash_matches),'/',nrow(manifest),'\n')
  if(any(!manifest$hash_matches))print(manifest[!manifest$hash_matches,c('dataset_id','raw_path','exists','hash_matches')])
  stopifnot(all(manifest$hash_matches))
  probes<-utils::read.csv('docs/raw_gap_probes.csv',stringsAsFactors=FALSE)
  probe_paths<-file.path('data/raw/sportsdataverse_raw/e2c40720c72a98f427f8964deba8dd0e22ff1303',paste0(probes$game_id,'.json'))
  stopifnot(all(file.exists(probe_paths)),identical(vapply(probe_paths,file_sha256,character(1),USE.NAMES=FALSE),probes$sha256))
  cat('Raw gap JSON hashes verified:',nrow(probes),'\n')
  unresolved<-DBI::dbGetQuery(con,"WITH errors AS (
    SELECT game_id,string_agg(DISTINCT stage || ': ' || regexp_replace(rule,' (espn:|[0-9]{5,}).*',''),'; ') categories
    FROM quality_exceptions WHERE version=? AND severity='error' GROUP BY game_id
  ), conflicts AS (
    SELECT game_id,count(*) failed_reference_checks,string_agg(DISTINCT metric,', ') failed_reference_metrics
    FROM reconciliation_checks WHERE passed IS FALSE GROUP BY game_id
  ) SELECT i.season,i.game_id,i.validation_status,
    coalesce(s.possessions_status,'not_reconstructed') possessions_status,
    coalesce(s.lineups_status,'not_reconstructed') lineups_status,
    coalesce(c.failed_reference_checks,0) failed_reference_checks,
    c.failed_reference_metrics,e.categories error_categories
  FROM schedule_inventory i LEFT JOIN reconstruction_status s ON i.game_id=s.game_id AND s.version=?
  LEFT JOIN conflicts c ON i.game_id=c.game_id LEFT JOIN errors e ON i.game_id=e.game_id
  WHERE i.validation_status='quarantined' OR s.possessions_status IS DISTINCT FROM 'reconciled' OR s.lineups_status IS DISTINCT FROM 'reconciled'
  ORDER BY i.season,i.game_id",params=list(reconstruction_version,reconstruction_version))
  utils::write.csv(unresolved,'docs/unresolved_games.csv',row.names=FALSE)
  disagreements<-DBI::dbGetQuery(con,'SELECT g.season,c.* FROM reconciliation_checks c JOIN games g USING(game_id) WHERE c.passed IS FALSE ORDER BY g.season,c.game_id,c.team_id,c.metric')
  utils::write.csv(disagreements,'docs/reference_disagreements.csv',row.names=FALSE)
  print(counts);print(integrity)
  # Include diagnostics and inventory changes made by the final report refresh.
  export_parquet(con)
},finally=DBI::dbDisconnect(con,shutdown=TRUE))

