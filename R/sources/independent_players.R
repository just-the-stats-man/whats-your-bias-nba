reference_player_sums <- function(path,team_path) {
  con<-DBI::dbConnect(duckdb::duckdb(),dbdir=':memory:')
  on.exit(DBI::dbDisconnect(con,shutdown=TRUE))
  file<-DBI::dbQuoteString(con,normalizePath(path,winslash='/'))
  team_file<-DBI::dbQuoteString(con,normalizePath(team_path,winslash='/'))
  sql<-sprintf("WITH p AS (
      SELECT *,lpad(CAST(TRY_CAST(gameId AS BIGINT) AS VARCHAR),10,'0') gid,
        CAST(TRY_CAST(playerteamId AS BIGINT) AS VARCHAR) raw_team,
        CASE WHEN TRY_CAST(personId AS DOUBLE)>0 AND TRY_CAST(personId AS DOUBLE)=trunc(TRY_CAST(personId AS DOUBLE)) THEN CAST(TRY_CAST(personId AS BIGINT) AS VARCHAR) ELSE NULL END athlete_key,
        CASE WHEN TRY_CAST(turnovers AS DOUBLE)>=0 AND TRY_CAST(turnovers AS DOUBLE)=trunc(TRY_CAST(turnovers AS DOUBLE)) THEN TRY_CAST(turnovers AS INTEGER) ELSE NULL END observed_tov,
        CASE WHEN lower(trim(home)) IN ('true','t','1','1.0') THEN TRUE WHEN lower(trim(home)) IN ('false','f','0','0.0') THEN FALSE ELSE NULL END home_flag
      FROM read_csv(%1$s,all_varchar=TRUE)
    ), team_base AS (
      SELECT DISTINCT lpad(CAST(TRY_CAST(gameId AS BIGINT) AS VARCHAR),10,'0') gid,
        CAST(TRY_CAST(teamId AS BIGINT) AS VARCHAR) team_id,
        CASE WHEN lower(trim(home)) IN ('true','t','1','1.0') THEN TRUE WHEN lower(trim(home)) IN ('false','f','0','0.0') THEN FALSE ELSE NULL END home_flag,
        lower(trim(teamName)) team_name,lower(trim(opponentTeamName)) opponent_name
      FROM read_csv(%2$s,all_varchar=TRUE)
    ), teams AS (
      SELECT *,count(*) OVER(PARTITION BY gid,home_flag) home_candidates,count(*) OVER(PARTITION BY gid,team_id) id_candidates FROM team_base
    ), resolved AS (
      SELECT p.*,
        CASE WHEN p.playerteamId IS NOT NULL THEN
          CASE WHEN k.team_id IS NOT NULL AND (p.home_flag IS NULL OR p.home_flag=k.home_flag) THEN p.raw_team ELSE NULL END
        WHEN h.team_id IS NOT NULL AND lower(trim(p.playerteamName))=h.team_name AND lower(trim(p.opponentteamName))=h.opponent_name THEN h.team_id ELSE NULL END resolved_team
      FROM p LEFT JOIN teams k ON p.gid=k.gid AND p.raw_team=k.team_id AND k.id_candidates=1
      LEFT JOIN teams h ON p.gid=h.gid AND p.home_flag=h.home_flag AND h.home_candidates=1
    ), flags AS (
      SELECT gid,bool_or(resolved_team IS NULL) unresolved_team FROM resolved GROUP BY gid
    )
    SELECT r.gid source_game_id,r.resolved_team nba_team_id,
      CASE WHEN bool_or(f.unresolved_team) OR count(*)!=count(DISTINCT athlete_key) OR count(*) FILTER (WHERE observed_tov IS NULL)>0 THEN NULL ELSE sum(observed_tov) END player_turnovers,
      count(*) player_rows,count(*) FILTER (WHERE playerteamId IS NULL AND resolved_team IS NOT NULL) mapped_team_rows,count(*) FILTER (WHERE resolved_team IS NULL) unresolved_team_rows
    FROM resolved r JOIN flags f ON r.gid=f.gid
    WHERE TRY_CAST(substr(r.gid,4,2) AS INTEGER) BETWEEN 15 AND 26
    GROUP BY r.gid,r.resolved_team",file,team_file)
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
  item$player_transform_id<-substr(digest::digest(list(body=body(reference_player_sums),team_sha256=item$sha256),algo='sha256'),1,12)
  cache<-paste0('data/processed/reference_player_sums_',item$player_sha256,'_',item$player_transform_id,'.parquet')
  if(file.exists(cache) && file.exists(paste0(cache,'.json'))) {
    item$player_totals<-as.data.frame(arrow::read_parquet(cache));item$player_row_count<-jsonlite::read_json(paste0(cache,'.json'))$raw_rows
  } else {
    item$player_totals<-reference_player_sums(path,item$path)
    item$player_row_count<-attr(item$player_totals,'raw_rows')
    dir.create(dirname(cache),recursive=TRUE,showWarnings=FALSE);arrow::write_parquet(item$player_totals,cache)
    jsonlite::write_json(list(raw_rows=item$player_row_count),paste0(cache,'.json'),auto_unbox=TRUE)
  }
  item
}
