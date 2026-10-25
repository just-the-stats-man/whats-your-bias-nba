source('scripts/load.R')
con<-connect_warehouse()
tryCatch({
  DBI::dbExecute(con,'SET threads=4')
  DBI::dbExecute(con,"SET memory_limit='3GB'")
  historical_schema(con)
  core<-assert_warehouse_integrity(con)
  utils::write.csv(core,'docs/warehouse_integrity.csv',row.names=FALSE)
  report<-historical_completeness(con)
  manifest<-DBI::dbReadTable(con,'historical_snapshots')
  manifest$actual_sha256<-vapply(manifest$path,file_sha256,character(1))
  manifest$hash_matches<-manifest$sha256==manifest$actual_sha256
  utils::write.csv(manifest,'data/processed/reports/historical_manifest_verification.csv',row.names=FALSE)
  stopifnot(all(manifest$hash_matches))
  prior<-DBI::dbReadTable(con,'datasets')
  stopifnot(all(file.exists(prior$raw_path)),all(vapply(prior$raw_path,file_sha256,character(1))==prior$sha256))
  probes<-utils::read.csv('docs/raw_gap_probes.csv',stringsAsFactors=FALSE)
  paths<-file.path('data/raw/sportsdataverse_raw/e2c40720c72a98f427f8964deba8dd0e22ff1303',paste0(probes$game_id,'.json'))
  stopifnot(all(file.exists(paths)),all(vapply(paths,file_sha256,character(1),USE.NAMES=FALSE)==probes$sha256))
  # Existing exports are the frozen, verified Phase 1 baseline. Compare every
  # original row using its primary key, allowing additive historical records.
  keys<-list(games='game_id',players='player_id',teams='team_id',
    team_identities=c('team_id','season'),player_identifiers=c('provider','provider_id'),
    player_box_scores=c('game_id','player_id'),team_box_scores=c('game_id','team_id'),
    pbp_events=c('game_id','event_id'),shot_attempts=c('game_id','event_id'),
    possessions='possession_id',possession_events=c('game_id','event_id'),
    non_possession_points=c('game_id','event_id'),lineups='lineup_id',
    lineup_players=c('lineup_id','player_id'),reconstruction_status='game_id',
    lineup_minute_checks=c('game_id','player_id'),pbp_reconciliation_checks=c('game_id','team_id','metric'),
    independent_team_totals=c('source_id','source_game_id','team_id'),
    reconciliation_checks=c('game_id','team_id','reference_dataset_id','metric'))
  preservation<-do.call(rbind,lapply(names(keys),function(table) {
    path<-file.path('data/processed/parquet',paste0(table,'.parquet'))
    if(!file.exists(path))return(data.frame(table=table,baseline_rows=NA,passed=FALSE))
    file<-DBI::dbQuoteString(con,normalizePath(path,winslash='/'))
    checksum<-function(query) {
      z<-DBI::dbGetQuery(con,paste0('SELECT count(*) n,bit_xor(hash(x)) checksum FROM (',query,') x'))
      c(n=as.character(z$n),checksum=as.character(z$checksum))
    }
    baseline<-checksum(paste0('SELECT * FROM read_parquet(',file,')'))
    current<-checksum(paste0('SELECT t.* FROM ',table,' t SEMI JOIN read_parquet(',file,') b USING(',paste(keys[[table]],collapse=','),')'))
    data.frame(table=table,baseline_rows=as.numeric(baseline['n']),passed=identical(baseline,current),row.names=NULL)
  }))
  utils::write.csv(preservation,'docs/baseline_preservation.csv',row.names=FALSE)
  stopifnot(all(preservation$passed))
  # Keep the original exports as the preservation baseline.
  destination<-'data/processed/historical_parquet';dir.create(destination,recursive=TRUE,showWarnings=FALSE)
  for(table in grep('^historical_',DBI::dbListTables(con),value=TRUE))DBI::dbExecute(con,sprintf('COPY (SELECT * FROM %s) TO %s (FORMAT PARQUET)',DBI::dbQuoteIdentifier(con,table),DBI::dbQuoteString(con,normalizePath(file.path(destination,paste0(table,'.parquet')),mustWork=FALSE))))
  utils::write.csv(DBI::dbGetQuery(con,'SELECT * FROM historical_snapshots ORDER BY kind'),'docs/historical_snapshots.csv',row.names=FALSE)
  selected<-report[,c('season','source_games','player_box_games','player_team_validated_games','pbp_games','shot_rows','coordinate_rows','possession_games','lineup_games')]
  headings<-c('Season','NBA game records','Player box games','Box checks passed','NBA PBP games','Shot rows','Coordinate rows','Possession games','Lineup games')
  lines<-c('# Historical availability by season','',
    'Counts describe the pinned snapshots, not complete league history. Expected full-season denominators are unestablished; early seasons omit many games and franchises. NBA boxes/PBP/shots are separate observations from the strict ESPN canonical cohort. Box checks cover era-applicable player/team counts and scoring identities; they do not establish independent measurement. Possession/lineup counts retain the strict original gates.',
    '',paste0('| ',paste(headings,collapse=' | '),' |'),paste0('|',paste(rep('---',length(headings)),collapse='|'),'|'),
    apply(selected,1,function(z)paste0('| ',paste(z,collapse=' | '),' |')),
    '', 'See historical_completeness.csv for canonical counts, raw rows, tracking status and reference agreement; historical_reconciliation.csv for overlap checks. Detailed game-level exceptions and comparisons are in data/processed/reports/*.parquet locally. Coordinate rows count plausible recorded positions, not validated optical tracking. No defender assignments or tracking observations were added.')
  lines<-c(lines,'','Box-total agreement includes NBA-recovered boxes compared to their own NBA source. Use execution_reconciliation.csv and its independent flag for distinct-provider certification.')
  writeLines(lines,'docs/historical_completeness.md')
  print(data.frame(seasons=nrow(report),nba_games=sum(report$source_games),player_rows=sum(report$player_rows),pbp_games=sum(report$pbp_games),event_rows=sum(report$event_rows),shots=sum(report$shot_rows)))
  cat('Core integrity:',sum(core$passed),'/',nrow(core),'; historical integrity:',nrow(historical_integrity(con)),'checks; baseline tables:',sum(preservation$passed),'/',nrow(preservation),'; raw snapshots:',nrow(manifest),'\n')
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
