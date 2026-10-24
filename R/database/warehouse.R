connect_warehouse <- function(path = 'data/processed/nba.duckdb') {
  if (path != ':memory:') dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = path)
  sql <- paste(readLines('config/schema.sql', warn = FALSE), collapse = '\n')
  for (statement in strsplit(sql, ';', fixed = TRUE)[[1]]) {
    if (nzchar(trimws(statement))) DBI::dbExecute(con, statement)
  }
  migrations <- c(
    'games ADD COLUMN IF NOT EXISTS competition VARCHAR',
    'schedule_inventory ADD COLUMN IF NOT EXISTS competition VARCHAR',
    'player_box_scores ADD COLUMN IF NOT EXISTS starter BOOLEAN',
    'team_box_scores ADD COLUMN IF NOT EXISTS total_turnovers INTEGER',
    'pbp_events ADD COLUMN IF NOT EXISTS secondary_player_id VARCHAR',
    'pbp_events ADD COLUMN IF NOT EXISTS tertiary_player_id VARCHAR',
    'pbp_events ADD COLUMN IF NOT EXISTS type_id INTEGER',
    'pbp_events ADD COLUMN IF NOT EXISTS shooting_play BOOLEAN',
    'pbp_events ADD COLUMN IF NOT EXISTS scoring_play BOOLEAN',
    'pbp_events ADD COLUMN IF NOT EXISTS score_value INTEGER',
    'pbp_events ADD COLUMN IF NOT EXISTS points_attempted INTEGER',
    'lineups ADD COLUMN IF NOT EXISTS period INTEGER',
    'lineups ADD COLUMN IF NOT EXISTS start_seconds DOUBLE',
    'lineups ADD COLUMN IF NOT EXISTS end_seconds DOUBLE',
    'lineups ADD COLUMN IF NOT EXISTS duration_seconds DOUBLE',
    'reconstruction_status ADD COLUMN IF NOT EXISTS dataset_id VARCHAR',
    'reconstruction_status ADD COLUMN IF NOT EXISTS reference_signature VARCHAR')
  migrations<-c(migrations,'independent_team_totals ADD COLUMN IF NOT EXISTS total_turnovers INTEGER','reconciliation_checks ADD COLUMN IF NOT EXISTS independent BOOLEAN')
  migrations<-c(migrations,'independent_team_totals ADD COLUMN IF NOT EXISTS reported_turnovers INTEGER')
  migrations<-c(migrations,'possessions ADD COLUMN IF NOT EXISTS start_seconds DOUBLE','possessions ADD COLUMN IF NOT EXISTS end_seconds DOUBLE','possessions ADD COLUMN IF NOT EXISTS duration_seconds DOUBLE')
  migrations<-c(migrations,'pbp_reconciliation_checks ADD COLUMN IF NOT EXISTS benchmark_type VARCHAR','pbp_reconciliation_checks ADD COLUMN IF NOT EXISTS benchmark_dataset_id VARCHAR','pbp_reconciliation_checks ADD COLUMN IF NOT EXISTS benchmark_game_id VARCHAR','pbp_reconciliation_checks ADD COLUMN IF NOT EXISTS benchmark_value DOUBLE')
  migrations<-c(migrations,'independent_team_totals ADD COLUMN IF NOT EXISTS mapped_player_team_rows INTEGER','independent_team_totals ADD COLUMN IF NOT EXISTS reference_player_rows INTEGER')
  for (migration in migrations) DBI::dbExecute(con,paste('ALTER TABLE',migration))
  DBI::dbExecute(con,'ALTER TABLE reconciliation_checks ALTER COLUMN passed DROP NOT NULL')
  con
}

upsert_rows <- function(con, table, rows, keys) {
  if (!nrow(rows)) return(invisible(NULL))
  if (anyNA(rows[keys]) || anyDuplicated(rows[keys])) stop('Missing or duplicate identifiers: ', table)
  DBI::dbWriteTable(con, '_incoming', rows, temporary = TRUE, overwrite = TRUE)
  on.exit(DBI::dbRemoveTable(con, '_incoming'), add = TRUE)
  cols <- paste(DBI::dbQuoteIdentifier(con, names(rows)), collapse = ', ')
  match <- paste(sprintf('t."%s" = s."%s"', keys, keys), collapse = ' AND ')
  DBI::dbExecute(con, sprintf('DELETE FROM "%s" t USING _incoming s WHERE %s', table, match))
  DBI::dbExecute(con, sprintf('INSERT INTO "%s" (%s) SELECT %s FROM _incoming', table, cols, cols))
  invisible(nrow(rows))
}

export_parquet <- function(con, directory = 'data/processed/parquet') {
  dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  tables <- setdiff(DBI::dbListTables(con), c('_incoming','_selected_games'))
  # Stream through DuckDB rather than materialize multi-million-row tables in R.
  for (table in tables) DBI::dbExecute(con,sprintf('COPY (SELECT * FROM %s) TO %s (FORMAT PARQUET)',DBI::dbQuoteIdentifier(con,table),DBI::dbQuoteString(con,normalizePath(file.path(directory,paste0(table,'.parquet')),mustWork=FALSE))))
  invisible(directory)
}
