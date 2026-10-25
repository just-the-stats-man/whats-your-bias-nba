# Reference expansion is deliberately separate from normalize_reference(): its
# modern IDs, turnover benchmarks and checkpoint signatures remain unchanged.
import_historical_reference <- function(con,seasons,directory='data/processed/reference') {
  if(any(vapply(seasons,season_end,integer(1))>=2016L))stop('Historical reference adapter cannot replace verified modern seasons')
  historical_schema(con)
  snapshots<-DBI::dbReadTable(con,'historical_snapshots')
  needed<-snapshots[snapshots$kind%in%c('team','player'),]
  parents<-snapshots[snapshots$kind%in%c('games','team','player'),]
  if(nrow(needed)!=2L)stop('One pinned historical team/player snapshot required')
  if(nrow(parents)!=3L)stop('Historical game metadata parent required')
  stopifnot(all(vapply(needed$path,file_sha256,character(1))==needed$sha256))
  map<-utils::read.csv('config/team_crosswalk.csv',colClasses='character')
  DBI::dbWriteTable(con,'_historical_reference_map',data.frame(team_id=paste0('espn:',map$espn_id),nba_team=paste0('nba:',map$nba_id)),temporary=TRUE,overwrite=TRUE)
  team_file<-needed$path[needed$kind=='team']
  DBI::dbExecute(con,paste0("CREATE OR REPLACE TEMP TABLE _historical_components AS SELECT 'nba:'||",historical_sql_id('gameId')," game_id,'nba:'||teamId team_id,CASE WHEN TRY_CAST(turnoversTeam AS DOUBLE)>=0 AND TRY_CAST(turnoversTeam AS DOUBLE)=trunc(TRY_CAST(turnoversTeam AS DOUBLE)) THEN TRY_CAST(turnoversTeam AS INTEGER) END team_turnovers FROM read_csv(",DBI::dbQuoteString(con,normalizePath(team_file,winslash='/')),",all_varchar=TRUE)"))
  # Register raw parents in the existing graph, in addition to the historical registry.
  DBI::dbExecute(con,"INSERT OR IGNORE INTO sources VALUES ('eoin_moore_nba','https://www.kaggle.com/datasets/eoinamoore/historical-nba-data-and-player-box-scores','CC0-1.0 publisher declaration','Eoin Moore; NBA.com upstream')")
  for(i in seq_len(nrow(parents))) {
    s<-parents[i,]
    upsert_rows(con,'datasets',data.frame(dataset_id=s$snapshot_id,source_id=s$source_id,url=s$url,revision=s$revision,retrieved_at=file.info(s$path)$mtime,sha256=s$sha256,raw_path=s$path,row_count=s$raw_rows),'dataset_id')
  }
  transform<-substr(digest::digest(body(import_historical_reference),algo='sha256'),1,16)
  for(season in seasons) {
    q<-DBI::dbQuoteString(con,season)
    fields<-paste(vapply(c('points','fgm','fga','fg3m','fg3a','ftm','fta','assists'),function(m)paste0('CAST(t.',m,' AS INTEGER) ',m),character(1)),collapse=',')
    sql<-paste0("WITH p AS (SELECT game_id,team_id,count(*) n,count(DISTINCT player_id) unique_players,count(*) FILTER (WHERE turnovers_status!='observed' OR validation_status='failed_validation') unknown_count,sum(turnovers) measured_sum,count(*) FILTER (WHERE identity_evidence='same-provider game/home/opponent ID') mapped_rows FROM historical_player_boxes WHERE season=",q," GROUP BY game_id,team_id), base AS (SELECT g.source_game_id,g.season,g.game_date,m.team_id,a.team_id opponent_team_id,t.team_id=g.home_team_id home,",fields,",CASE WHEN p.unknown_count=0 AND p.n=p.unique_players AND NOT EXISTS (SELECT 1 FROM historical_player_boxes b WHERE b.game_id=t.game_id AND (b.team_id IS NULL OR b.validation_status='failed_validation')) THEN CAST(p.measured_sum AS INTEGER) END turnovers,CAST(t.turnovers AS INTEGER) reported_turnovers,c.team_turnovers,CAST(p.mapped_rows AS INTEGER) mapped_player_team_rows,CAST(p.n AS INTEGER) reference_player_rows FROM historical_team_boxes t JOIN historical_games g USING(game_id) JOIN _historical_reference_map m ON t.team_id=m.nba_team JOIN _historical_reference_map a ON a.nba_team=CASE WHEN t.team_id=g.home_team_id THEN g.away_team_id ELSE g.home_team_id END LEFT JOIN p ON p.game_id=t.game_id AND p.team_id=t.team_id LEFT JOIN _historical_components c ON c.game_id=t.game_id AND c.team_id=t.team_id WHERE g.season=",q," AND t.validation_status='observed' AND (g.start_year>=2002 OR (m.team_id!='espn:3' AND a.team_id!='espn:3')) AND (g.start_year>=2004 OR (m.team_id!='espn:30' AND a.team_id!='espn:30'))) SELECT *,turnovers+team_turnovers total_turnovers FROM base")
    d<-DBI::dbGetQuery(con,sql);d$team_turnovers<-NULL
    if(!nrow(d))next
    d$source_id<-'eoin_moore_nba'
    d$dataset_id<-paste0('nba-history-reference:',season,':',paste(sort(parents$sha256),collapse=':'),':',transform)
    dir.create(directory,recursive=TRUE,showWarnings=FALSE)
    input_id<-substr(digest::digest(sort(parents$sha256),algo='sha256'),1,16)
    path<-file.path(directory,paste0('historical_',season,'_',input_id,'_',transform,'.parquet'))
    arrow::write_parquet(d,path)
    DBI::dbWithTransaction(con,{
      upsert_rows(con,'datasets',data.frame(dataset_id=unique(d$dataset_id),source_id='eoin_moore_nba',url='https://www.kaggle.com/datasets/eoinamoore/historical-nba-data-and-player-box-scores',revision='historical-v524',retrieved_at=Sys.time(),sha256=file_sha256(path),raw_path=path,row_count=nrow(d)),'dataset_id')
      upsert_rows(con,'dataset_dependencies',data.frame(dataset_id=unique(d$dataset_id),parent_dataset_id=parents$snapshot_id,transformation='Historical NBA reference; game date/identity metadata and known player turnover sums plus explicitly recorded team-only component; namespace mapping guards Charlotte history'),c('dataset_id','parent_dataset_id'))
      upsert_rows(con,'independent_team_totals',d,c('source_id','source_game_id','team_id'))
    })
  }
  invisible(NULL)
}

reconcile_historical_scope <- function(con,seasons) {
  if(any(vapply(seasons,season_end,integer(1))>=2016L))stop('Historical reconciliation cannot refresh verified modern seasons')
  selected<-paste(DBI::dbQuoteString(con,seasons),collapse=',')
  read_checks<-function(table,order)DBI::dbGetQuery(con,paste0('SELECT c.* FROM ',table,' c JOIN _history_protected_status p USING(game_id) ORDER BY ',order))
  DBI::dbWithTransaction(con,{
    DBI::dbExecute(con,paste0('CREATE OR REPLACE TEMP TABLE _history_protected_status AS SELECT * FROM reconstruction_status WHERE season NOT IN (',selected,')'))
    checks<-read_checks('reconciliation_checks','c.game_id,c.team_id,c.reference_dataset_id,c.metric')
    pbp<-read_checks('pbp_reconciliation_checks','c.game_id,c.team_id,c.metric')
    reconcile_game_totals_impl(con)
    if(!identical(checks,read_checks('reconciliation_checks','c.game_id,c.team_id,c.reference_dataset_id,c.metric')) || !identical(pbp,read_checks('pbp_reconciliation_checks','c.game_id,c.team_id,c.metric')))stop('Historical refresh changed a protected benchmark; rolled back')
    # Preserve microsecond timestamps in SQL, without an R POSIXct round-trip.
    DBI::dbExecute(con,'DELETE FROM reconstruction_status WHERE game_id IN (SELECT game_id FROM _history_protected_status)')
    DBI::dbExecute(con,'INSERT INTO reconstruction_status BY NAME SELECT * FROM _history_protected_status')
  })
  invisible(NULL)
}
