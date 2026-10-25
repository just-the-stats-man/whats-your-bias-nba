# Additive NBA observations. Never changes the ESPN canonical/reconstruction tables.
historical_statuses <- c('observed','reconstructed','estimated','not_collected',
                        'source_missing','failed_validation','not_licensed','not_applicable')

historical_metrics <- function() utils::read.csv('config/historical_metrics.csv',stringsAsFactors=FALSE)

nba_season_start <- function(game_id,date) {
  id<-sprintf('%010.0f',suppressWarnings(as.numeric(game_id)))
  year<-suppressWarnings(as.integer(substr(as.character(date),1,4)))
  suffix<-suppressWarnings(as.integer(substr(id,4,5)))
  valid<-grepl('^[0-9]{10}$',id) & !is.na(year) & !is.na(suffix)
  out<-rep(NA_integer_,length(id))
  a<-valid & year%%100L==suffix;b<-valid & (year-1L)%%100L==suffix
  out[which(a & !b)]<-year[which(a & !b)]
  out[which(b & !a)]<-year[which(b & !a)]-1L
  out
}

historical_schema <- function(con) {
  DBI::dbExecute(con,"CREATE TABLE IF NOT EXISTS historical_snapshots (snapshot_id VARCHAR PRIMARY KEY, source_id VARCHAR, upstream VARCHAR, revision VARCHAR, kind VARCHAR, path VARCHAR, url VARCHAR, sha256 VARCHAR, raw_rows BIGINT)")
  DBI::dbExecute(con,"CREATE TABLE IF NOT EXISTS historical_checkpoints (snapshot_id VARCHAR, season VARCHAR, transform_id VARCHAR, completed_at TIMESTAMP, PRIMARY KEY(snapshot_id,season))")
  DBI::dbExecute(con,"CREATE TABLE IF NOT EXISTS historical_games (game_id VARCHAR PRIMARY KEY, source_game_id VARCHAR, season VARCHAR, start_year INTEGER, competition VARCHAR, game_date DATE, home_team_id VARCHAR, away_team_id VARCHAR, home_score INTEGER, away_score INTEGER, source_row BIGINT, snapshot_id VARCHAR)")
  defs<-unlist(lapply(historical_metrics()$metric,function(m)c(paste(m,'DOUBLE'),paste0(m,'_status VARCHAR CHECK (',m,'_status IN (',paste(sprintf("'%s'",historical_statuses),collapse=','),'))'))))
  for(kind in c('team','player')) {
    extra<-if(kind=='player')'player_id VARCHAR, identity_evidence VARCHAR,' else ''
    DBI::dbExecute(con,paste0('CREATE TABLE IF NOT EXISTS historical_',kind,'_boxes (snapshot_id VARCHAR, source_row BIGINT, game_id VARCHAR, season VARCHAR, team_id VARCHAR, ',extra,' validation_status VARCHAR, ',paste(defs,collapse=', '),', PRIMARY KEY(snapshot_id,source_row))'))
  }
  DBI::dbExecute(con,"CREATE TABLE IF NOT EXISTS historical_exceptions (snapshot_id VARCHAR, source_row BIGINT, family VARCHAR, game_id VARCHAR, season VARCHAR, rule VARCHAR)")
  DBI::dbExecute(con,"CREATE TABLE IF NOT EXISTS historical_box_checks (game_id VARCHAR, team_id VARCHAR, season VARCHAR, metric VARCHAR, player_sum DOUBLE, team_value DOUBLE, status VARCHAR)")
  DBI::dbExecute(con,"CREATE TABLE IF NOT EXISTS historical_events (snapshot_id VARCHAR, source_row BIGINT, game_id VARCHAR, season VARCHAR, event_id VARCHAR, period INTEGER, clock VARCHAR, event_type VARCHAR, description VARCHAR, team_id VARCHAR, player_id VARCHAR, home_score INTEGER, away_score INTEGER, PRIMARY KEY(snapshot_id,source_row))")
  DBI::dbExecute(con,"CREATE TABLE IF NOT EXISTS historical_shots (snapshot_id VARCHAR, source_row BIGINT, game_id VARCHAR, season VARCHAR, player_id VARCHAR, team_id VARCHAR, made BOOLEAN, points_attempted INTEGER, points_status VARCHAR, x DOUBLE, y DOUBLE, x_legacy DOUBLE, y_legacy DOUBLE, coordinate_system VARCHAR, coordinate_status VARCHAR, distance DOUBLE, distance_status VARCHAR, PRIMARY KEY(snapshot_id,source_row))")
  DBI::dbExecute(con,"ALTER TABLE historical_shots ADD COLUMN IF NOT EXISTS distance_status VARCHAR")
  invisible(con)
}

historical_file <- function(kind,version=524L,download=TRUE) {
  files<-c(games='Games.csv',team='TeamStatistics.csv',player='PlayerStatistics.csv',pbp='PlayByPlay.parquet',players='Players.csv',teams='TeamHistories.csv')
  name<-files[[kind]];if(is.null(name))stop('Unknown historical family')
  path<-file.path('data/raw/independent',sub('[.]',paste0('_v',version,'.'),name))
  url<-paste0('https://www.kaggle.com/api/v1/datasets/download/eoinamoore/historical-nba-data-and-player-box-scores/',name,'?datasetVersionNumber=',as.integer(version))
  metadata<-file.path('data/raw/independent',paste0('kaggle_metadata_',version,'.json'))
  if(!file.exists(metadata) || jsonlite::read_json(metadata)$licenseName!='CC0: Public Domain')stop('Pinned publisher license metadata required')
  if(!file.exists(path)) {
    if(!download)stop('Historical file not cached: ',path)
    dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE)
    tmp<-paste0(path,'.partial');on.exit(if(file.exists(tmp))unlink(tmp),add=TRUE)
    httr2::request(url) |> httr2::req_timeout(1200) |> httr2::req_retry(max_tries=3) |> httr2::req_perform(path=tmp)
    if(grepl('parquet$',name))arrow::open_dataset(tmp,format='parquet') else if(length(strsplit(readLines(tmp,n=1,warn=FALSE),',')[[1]])<3)stop('Unexpected CSV response')
    if(!file.rename(tmp,path))stop('Historical cache write failed')
  }
  list(kind=kind,path=path,url=url,revision=paste0('kaggle-v',version),sha256=file_sha256(path))
}

historical_raw <- function(con,item) {
  # A physical row ordinal is a raw pointer, not a cross-provider event identity.
  reader<-if(item$kind=='pbp')'read_parquet' else 'read_csv'
  extra<-if(reader=='read_csv')',all_varchar=TRUE' else ''
  table<-paste0('_history_',item$kind)
  prior<-DBI::dbGetQuery(con,'SELECT sha256 FROM historical_snapshots WHERE path=?',params=list(item$path))$sha256
  if(length(prior) && any(prior!=item$sha256))stop('Raw path changed since registration: ',item$path)
  DBI::dbExecute(con,sprintf('CREATE OR REPLACE TEMP TABLE %s AS SELECT row_number() OVER () source_row,* FROM %s(%s%s)',table,reader,DBI::dbQuoteString(con,normalizePath(item$path,winslash='/')),extra))
  n<-as.numeric(DBI::dbGetQuery(con,paste('SELECT count(*) n FROM',table))$n)
  item$snapshot_id<-paste0('nba-history:',item$kind,':',item$sha256)
  upsert_rows(con,'historical_snapshots',data.frame(snapshot_id=item$snapshot_id,source_id='eoin_moore_nba',upstream='NBA.com',revision=item$revision,kind=item$kind,path=item$path,url=item$url,sha256=item$sha256,raw_rows=n),'snapshot_id')
  item
}

historical_sql_id <- function(column) paste0("lpad(CAST(TRY_CAST(",column," AS BIGINT) AS VARCHAR),10,'0')")

historical_prepare_games <- function(con,item) {
  id<-historical_sql_id('gameId')
  DBI::dbExecute(con,paste0("CREATE OR REPLACE TEMP TABLE _history_game_candidates AS WITH b AS (SELECT *,",id," gid,TRY_CAST(substr(gameDateTimeEst,1,10) AS DATE) dt FROM _history_games), y AS (SELECT *,year(dt) yr,TRY_CAST(substr(gid,4,2) AS INTEGER) suffix FROM b) SELECT *,CASE WHEN yr%100=suffix THEN yr WHEN (yr-1)%100=suffix THEN yr-1 ELSE NULL END start_year,count(*) OVER(PARTITION BY gid) copies FROM y"))
  q<-DBI::dbQuoteString(con,item$snapshot_id)
  DBI::dbExecute(con,paste0("INSERT INTO historical_exceptions SELECT ",q,",source_row,'games','nba:'||gid,NULL,'ambiguous season, duplicate game, missing identity or invalid score' FROM _history_game_candidates WHERE start_year IS NULL OR copies!=1 OR hometeamId IS NULL OR awayteamId IS NULL OR hometeamId=awayteamId OR TRY_CAST(homeScore AS INTEGER)<=0 OR TRY_CAST(awayScore AS INTEGER)<=0 OR TRY_CAST(homeScore AS INTEGER) IS NULL OR TRY_CAST(awayScore AS INTEGER) IS NULL"))
  DBI::dbExecute(con,paste0("INSERT INTO historical_games SELECT 'nba:'||gid,gid,CAST(start_year AS VARCHAR)||'-'||right(CAST(start_year+1 AS VARCHAR),2),start_year,CASE substr(gid,1,3) WHEN '002' THEN 'regular' WHEN '004' THEN 'playoffs' WHEN '005' THEN 'play_in' WHEN '006' THEN 'cup_final' END,dt,'nba:'||hometeamId,'nba:'||awayteamId,TRY_CAST(homeScore AS INTEGER),TRY_CAST(awayScore AS INTEGER),source_row,",q," FROM _history_game_candidates WHERE substr(gid,1,3) IN ('002','004','005','006') AND start_year IS NOT NULL AND copies=1 AND hometeamId IS NOT NULL AND awayteamId IS NOT NULL AND hometeamId!=awayteamId AND TRY_CAST(homeScore AS INTEGER)>0 AND TRY_CAST(awayScore AS INTEGER)>0"))
}

historical_box_sql <- function(con,kind,snapshot_id,season) {
  metrics<-historical_metrics();q<-function(x)as.character(DBI::dbQuoteString(con,x))
  if(kind=='team') {
    source<-"r.*,g.*, 'nba:'||r.teamId resolved_team,CAST(NULL AS VARCHAR) player_key,'recorded NBA team ID' identity_evidence"
    join<-"'nba:'||r.teamId IN (g.home_team_id,g.away_team_id)"
  } else {
    # Missing team IDs resolve only via a unique recorded game, explicit home
    # flag and the recorded opposing NBA ID. No names or fuzzy joins.
    source<-paste0("r.*,g.*,CASE WHEN r.playerteamId IS NOT NULL THEN 'nba:'||r.playerteamId WHEN r.home='1' AND 'nba:'||r.opponentteamId=g.away_team_id THEN g.home_team_id WHEN r.home='0' AND 'nba:'||r.opponentteamId=g.home_team_id THEN g.away_team_id END resolved_team,CASE WHEN TRY_CAST(r.personId AS BIGINT)>0 THEN 'nba:'||r.personId END player_key,CASE WHEN r.playerteamId IS NOT NULL THEN 'recorded NBA team ID' ELSE 'same-provider game/home/opponent ID' END identity_evidence")
    join<-"TRUE"
  }
  raw<-vapply(seq_len(nrow(metrics)),function(i) {
    column<-metrics$source_column[i];if(kind=='team' && column=='points')column<-'teamScore'
    paste0('TRY_CAST(r.',column,' AS DOUBLE) raw_',metrics$metric[i])
  },character(1))
  status<-vapply(seq_len(nrow(metrics)),function(i) {
    m<-metrics$metric[i];x<-paste0('raw_',m)
    missing<-c(paste0(x,' IS NULL'))
    if(m%in%c('fga','fta','fg3a'))missing<-c(missing,paste0(x,'=0 AND raw_',c(fga='fgm',fta='ftm',fg3a='fg3m')[[m]],'>0'))
    if(m=='minutes')missing<-c(missing,if(kind=='team')paste0(x,'=0') else paste0(x,'=0 AND (raw_points>0 OR raw_fga>0 OR raw_fta>0 OR raw_rebounds>0 OR raw_fouls>0 OR raw_turnovers>0 OR raw_assists>0)'))
    if(kind=='team' && m%in%c('rebounds','assists'))missing<-c(missing,paste0(x,'=0'))
    if(kind=='player')missing<-c(missing,paste0("NOT EXISTS (SELECT 1 FROM historical_team_boxes t WHERE t.game_id=b.game_id AND t.team_id=b.resolved_team AND t.",m,"_status='observed')"))
    paste0("CASE WHEN start_year<",metrics$first_season_start[i]," THEN '",metrics$pre_era_status[i],"' WHEN ",paste(missing,collapse=' OR ')," THEN 'source_missing' WHEN ",x,"<0",if(m!='minutes')paste0(' OR ',x,'!=trunc(',x,')') else ''," THEN 'failed_validation' ELSE 'observed' END ",m,'_status')
  },character(1))
  # Do not admit duplicate entity rows into aggregate reconciliations.
  entity<-if(kind=='team')'resolved_team' else 'player_key'
  cte<-paste0("WITH b AS (SELECT ",source,',',paste(raw,collapse=',')," FROM _history_",kind," r JOIN historical_games g ON 'nba:'||",historical_sql_id('r.gameId'),"=g.game_id WHERE g.season=",q(season)," AND ",join,"), s AS (SELECT b.*,count(*) OVER(PARTITION BY game_id,",entity,") entity_copies,",paste(status,collapse=',')," FROM b), v AS (SELECT *,CASE WHEN resolved_team IS NULL OR resolved_team NOT IN (home_team_id,away_team_id) OR entity_copies!=1",if(kind=='player')" OR player_key IS NULL" else ''," THEN 'failed_validation' WHEN points_status!='observed' OR fgm_status!='observed' OR ftm_status!='observed' OR (start_year>=1979 AND fg3m_status!='observed') THEN 'source_missing' WHEN raw_points!=2*raw_fgm+CASE WHEN start_year<1979 THEN 0 ELSE raw_fg3m END+raw_ftm",if(kind=='team')" OR raw_points!=CASE WHEN resolved_team=home_team_id THEN home_score ELSE away_score END" else ''," THEN 'failed_validation' ELSE 'observed' END validation_status FROM s) ")
  columns<-unlist(lapply(metrics$metric,function(m)c(paste0("CASE WHEN ",m,"_status='observed' THEN raw_",m,' END AS "',m,'"'),paste0(m,'_status'))))
  paste0(cte,'SELECT ',q(snapshot_id)," snapshot_id,b.source_row,b.game_id,b.season,resolved_team team_id,",if(kind=='player')'player_key player_id,identity_evidence,',"validation_status,",paste(columns,collapse=','),' FROM v b')
}

historical_transform_id <- function() substr(digest::digest(lapply(c('R/sources/historical.R','R/ingestion/historical.R','config/historical_metrics.csv'),readLines,warn=FALSE),algo='sha256'),1,16)
