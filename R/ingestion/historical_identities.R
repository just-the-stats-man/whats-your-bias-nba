ingest_historical_identities <- function(con) {
  historical_schema(con)
  for(kind in c('players','teams')) {
    item<-historical_raw(con,historical_file(kind))
    if(kind=='players') {
      DBI::dbExecute(con,"CREATE TABLE IF NOT EXISTS historical_players (player_id VARCHAR PRIMARY KEY,source_person_id VARCHAR,name VARCHAR,source_row BIGINT,snapshot_id VARCHAR)")
      d<-DBI::dbGetQuery(con,paste0("WITH p AS (SELECT *,CAST(TRY_CAST(personId AS BIGINT) AS VARCHAR) person_key,count(*) OVER(PARTITION BY TRY_CAST(personId AS BIGINT)) copies FROM _history_players) SELECT 'nba:'||person_key player_id,person_key source_person_id,concat_ws(' ',firstName,lastName) AS \"name\",source_row,",DBI::dbQuoteString(con,item$snapshot_id)," snapshot_id FROM p WHERE TRY_CAST(personId AS BIGINT)>0 AND TRY_CAST(personId AS DOUBLE)=trunc(TRY_CAST(personId AS DOUBLE)) AND copies=1"))
      upsert_rows(con,'historical_players',d,'player_id')
    } else {
      DBI::dbExecute(con,"CREATE TABLE IF NOT EXISTS historical_team_history (snapshot_id VARCHAR,source_row BIGINT,team_id VARCHAR,city VARCHAR,name VARCHAR,abbreviation VARCHAR,season_founded_raw VARCHAR,season_active_till_raw VARCHAR,league_raw VARCHAR,evidence VARCHAR,PRIMARY KEY(snapshot_id,source_row))")
      d<-DBI::dbGetQuery(con,paste0("SELECT ",DBI::dbQuoteString(con,item$snapshot_id)," snapshot_id,source_row,'nba:'||teamId team_id,teamCity city,teamName AS \"name\",teamAbbrev abbreviation,seasonFounded season_founded_raw,seasonActiveTill season_active_till_raw,league league_raw,'provider labels; not a validated franchise reassignment crosswalk' evidence FROM _history_teams"))
      upsert_rows(con,'historical_team_history',d,c('snapshot_id','source_row'))
    }
  }
  invisible(NULL)
}
