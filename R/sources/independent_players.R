reference_player_sums <- function(path) {
  con<-DBI::dbConnect(duckdb::duckdb(),dbdir=':memory:')
  on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  file<-DBI::dbQuoteString(con,normalizePath(path,winslash='/'))
  sql<-sprintf("SELECT lpad(CAST(TRY_CAST(gameId AS BIGINT) AS VARCHAR),10,'0') source_game_id, CAST(TRY_CAST(playerteamId AS BIGINT) AS VARCHAR) nba_team_id,
    CASE WHEN count(*)!=count(DISTINCT personId) OR count(*) FILTER (WHERE TRY_CAST(turnovers AS INTEGER) IS NULL AND (TRY_CAST(numMinutes AS DOUBLE)>0 OR (numMinutes IS NULL AND coalesce(comment,'')='')))>0 THEN NULL ELSE sum(coalesce(TRY_CAST(turnovers AS INTEGER),0)) END player_turnovers,
    count(*) player_rows FROM read_csv(%s,all_varchar=TRUE)
    WHERE TRY_CAST(substr(lpad(gameId,10,'0'),4,2) AS INTEGER) BETWEEN 15 AND 26
    GROUP BY source_game_id,nba_team_id",file)
  out<-DBI::dbGetQuery(con,sql)
  attr(out,'raw_rows')<-as.numeric(DBI::dbGetQuery(con,sprintf('SELECT count(*) FROM read_csv(%s,all_varchar=TRUE)',file))[[1]][1])
  out
}

attach_reference_players <- function(item,path=NULL,version=reference_version,download=TRUE) {
  if(is.null(path))path<-paste0('data/raw/independent/PlayerStatistics_v',version,'.csv')
  url<-paste0('https://www.kaggle.com/api/v1/datasets/download/eoinamoore/historical-nba-data-and-player-box-scores/PlayerStatistics.csv?datasetVersionNumber=',version)
  if(!file.exists(path)) {
    if(!download)stop('Offline independent player fixture is missing')
    response<-httr2::request(url) |> httr2::req_timeout(300) |> httr2::req_retry(max_tries=3) |> httr2::req_perform()
    tmp<-tempfile(tmpdir=dirname(path));on.exit(unlink(tmp),add=TRUE)
    writeBin(httr2::resp_body_raw(response),tmp)
    if(!grepl('personId,gameId',readLines(tmp,n=1,warn=FALSE),fixed=TRUE))stop('Unexpected independent player schema')
    if(!file.rename(tmp,path))stop('Unable to preserve independent player source')
  }
  item$player_path<-path;item$player_url<-url;item$player_sha256<-file_sha256(path)
  item$player_transform_id<-substr(digest::digest(body(reference_player_sums),algo='sha256'),1,12)
  cache<-paste0('data/processed/reference_player_sums_',item$player_sha256,'_',item$player_transform_id,'.parquet')
  if(file.exists(cache) && file.exists(paste0(cache,'.json'))) {
    item$player_totals<-as.data.frame(arrow::read_parquet(cache));item$player_row_count<-jsonlite::read_json(paste0(cache,'.json'))$raw_rows
  } else {
    item$player_totals<-reference_player_sums(path)
    item$player_row_count<-attr(item$player_totals,'raw_rows')
    dir.create(dirname(cache),recursive=TRUE,showWarnings=FALSE);arrow::write_parquet(item$player_totals,cache)
    jsonlite::write_json(list(raw_rows=item$player_row_count),paste0(cache,'.json'),auto_unbox=TRUE)
  }
  item
}
