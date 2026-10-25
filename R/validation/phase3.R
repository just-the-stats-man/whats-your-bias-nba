phase3_snapshot_connection <- function() {
  con<-DBI::dbConnect(duckdb::duckdb(),dbdir=':memory:')
  DBI::dbExecute(con,'SET threads=4');DBI::dbExecute(con,"SET memory_limit='2GB'")
  for(path in c(list.files('data/processed/execution_parquet',pattern='[.]parquet$',full.names=TRUE),list.files('data/processed/historical_parquet',pattern='[.]parquet$',full.names=TRUE))) {
    table<-sub('[.]parquet$','',basename(path))
    DBI::dbExecute(con,paste0('CREATE VIEW ',table,' AS SELECT * FROM read_parquet(',DBI::dbQuoteString(con,normalizePath(path,winslash='/')),')'))
  }
  con
}
