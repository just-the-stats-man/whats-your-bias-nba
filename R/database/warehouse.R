connect_warehouse <- function(path = 'data/processed/nba.duckdb') {
  if (path != ':memory:') dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = path)
  sql <- paste(readLines('config/schema.sql', warn = FALSE), collapse = '\n')
  for (statement in strsplit(sql, ';', fixed = TRUE)[[1]]) {
    if (nzchar(trimws(statement))) DBI::dbExecute(con, statement)
  }
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
  tables <- setdiff(DBI::dbListTables(con), '_incoming')
  for (table in tables) arrow::write_parquet(DBI::dbReadTable(con, table), file.path(directory, paste0(table, '.parquet')))
  invisible(directory)
}
