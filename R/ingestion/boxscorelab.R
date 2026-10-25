boxscorelab_game_checks <- function(x) {
  n<-function(k)suppressWarnings(as.numeric(x[[k]]))
  numeric_ok<-n('points')==2*n('field_goals_made')+n('three_point_makes')+n('free_throws_made') & n('field_goals_made')<=n('field_goal_attempts') & n('three_point_makes')<=n('three_point_attempts') & n('free_throws_made')<=n('free_throw_attempts') & n('point_diff')==n('points')-n('opponent_points') & n('rebounds')==n('offensive_rebounds')+n('defensive_rebounds')
  key<-paste(x$season,x$game_date,x$team,x$opponent)
  j<-match(paste(x$season,x$game_date,x$opponent,x$team),key)
  paired<-!is.na(j) & n('points')==n('opponent_points')[j] & n('opponent_points')==n('points')[j] & x$home!=x$home[j]
  result<-numeric_ok & paired & !duplicated(key) & !duplicated(key,fromLast=TRUE) & x$home%in%c('True','False') & ((x$result=='W' & n('points')>n('opponent_points')) | (x$result=='L' & n('points')<n('opponent_points')))
  result[is.na(result)]<-FALSE;result
}

ingest_boxscorelab <- function(con,folder='data/raw/boxscorelab/build-20261025T1216') {
  receipt<-file.path(folder,'downloads.html');license<-paste(readLines(receipt,warn=FALSE),collapse='\n')
  if(!grepl('CC BY 4.0',license,fixed=TRUE) || !grepl('20261025T1216',license,fixed=TRUE))stop('Pinned licensed build receipt required')
  source<-'boxscorelab';url<-'https://boxscorelab.com/downloads/'
  upsert_rows(con,'sources',data.frame(source_id=source,url=url,license='CC BY 4.0 (downloaded CSVs); NBA Stats upstream',attribution='BoxScore Lab, https://boxscorelab.com; build 20261025T1216; counting fields only for reconciliation, provider modeled rates remain separate'),'source_id')
  register<-function(path,rows) {
    prior<-DBI::dbGetQuery(con,'SELECT sha256 FROM datasets WHERE raw_path=?',params=list(path))$sha256
    if(length(prior) && any(prior!=file_sha256(path)))stop('Registered BoxScore Lab input path changed')
    id<-paste0('boxscorelab:',basename(path),':',file_sha256(path))
    upsert_rows(con,'datasets',data.frame(dataset_id=id,source_id=source,url=paste0(url,if(grepl('csv$',path))basename(path) else ''),revision='build-20261025T1216',retrieved_at=file.info(path)$mtime,sha256=file_sha256(path),raw_path=path,row_count=rows),'dataset_id');id
  }
  parent<-register(receipt,1)
  register(file.path(folder,'methodology.html'),1)
  for(kind in c('player-season-totals','team-standings','team-game-results')) {
    table<-paste0('boxscorelab_',gsub('-','_',kind))
    for(season in season_label(2023:2027)) {
      path<-file.path(folder,paste0(season,'-',kind,'.csv'));stopifnot(file.exists(path))
      x<-utils::read.csv(path,colClasses='character',check.names=FALSE)
      stopifnot(all(x$season==season))
      id<-paste0('boxscorelab:',basename(path),':',file_sha256(path))
      if(DBI::dbExistsTable(con,table) && nrow(DBI::dbGetQuery(con,paste0('SELECT dataset_id FROM ',table,' WHERE dataset_id=? LIMIT 1'),params=list(id))))next
      x$dataset_id<-id;x$source_row<-seq_len(nrow(x))
      x$provider_key<-if(kind=='team-game-results')paste(season,x$game_date,x$team,x$opponent,x$home,sep=':') else if(kind=='team-standings')paste(season,x$team,sep=':') else paste(season,x$player_name,sep=':')
      if(anyDuplicated(x$provider_key))stop('Ambiguous provider-native key')
      if(kind=='team-game-results')x$validation_status<-ifelse(boxscorelab_game_checks(x),'observed','failed_validation')
      if(kind=='team-standings') {
        ok<-as.numeric(x$wins)+as.numeric(x$losses)==as.numeric(x$games)
        x$validation_status<-ifelse(ok,'observed','failed_validation')
      }
      if(kind=='player-season-totals') {
        # The team label can be the last team, while counts combine all stints.
        ok<-as.numeric(x$points)==2*as.numeric(x$field_goals_made)+as.numeric(x$three_point_makes)+as.numeric(x$free_throws_made)
        x$validation_status<-ifelse(ok,'observed','failed_validation')
      }
      x$upstream<-'NBA Stats; not independent measurement of other NBA-derived feeds'
      DBI::dbWithTransaction(con,{
        register(path,nrow(x))
        upsert_rows(con,'dataset_dependencies',data.frame(dataset_id=id,parent_dataset_id=parent,transformation='Publisher CSV preserved by native season/team or season/player name; no inferred canonical identities; modeled ratios not observational totals'),c('dataset_id','parent_dataset_id'))
        if(!DBI::dbExistsTable(con,table))DBI::dbWriteTable(con,table,x) else DBI::dbAppendTable(con,table,x)
      })
    }
  }
  invisible(NULL)
}

boxscorelab_reports <- function(con,directory='docs') {
  map<-utils::read.csv('config/boxscorelab_team_crosswalk.csv',colClasses='character')
  stopifnot(nrow(map)==30L,!anyDuplicated(map$abbreviation),!anyDuplicated(map$nba_id))
  DBI::dbWriteTable(con,'_bsl_map',map,temporary=TRUE,overwrite=TRUE)
  DBI::dbExecute(con,"CREATE OR REPLACE TEMP TABLE _bsl_games AS SELECT b.dataset_id,b.source_row,g.game_id FROM boxscorelab_team_game_results b JOIN _bsl_map t ON b.team=t.abbreviation JOIN _bsl_map o ON b.opponent=o.abbreviation JOIN historical_games g ON g.season=b.season AND CAST(b.game_date AS DATE)=g.game_date AND 'nba:'||t.nba_id=CASE WHEN b.home='True' THEN g.home_team_id ELSE g.away_team_id END AND 'nba:'||o.nba_id=CASE WHEN b.home='True' THEN g.away_team_id ELSE g.home_team_id END WHERE g.competition='regular' QUALIFY count(*) OVER(PARTITION BY b.dataset_id,b.source_row)=1")
  DBI::dbExecute(con,'CREATE OR REPLACE TABLE boxscorelab_reconciliation (dataset_id VARCHAR,source_row BIGINT,season VARCHAR,game_id VARCHAR,team_id VARCHAR,metric VARCHAR,provider_value DOUBLE,nba_value DOUBLE,status VARCHAR,independent BOOLEAN)')
  metrics<-c(points='points',field_goals_made='fgm',field_goal_attempts='fga',three_point_makes='fg3m',three_point_attempts='fg3a',free_throws_made='ftm',free_throw_attempts='fta',assists='assists',turnovers='turnovers')
  for(k in names(metrics)) {
    m<-metrics[[k]]
    # These feeds share NBA upstream. This is a consistency diagnostic only.
    DBI::dbExecute(con,paste0("INSERT INTO boxscorelab_reconciliation SELECT b.dataset_id,b.source_row,b.season,l.game_id,'nba:'||m.nba_id,'",m,"',TRY_CAST(b.",k," AS DOUBLE),t.",m,",CASE WHEN b.validation_status!='observed' THEN 'failed_source_validation' WHEN t.game_id IS NULL THEN 'unmatched' WHEN t.",m,"_status!='observed' OR t.",m," IS NULL THEN 'source_missing' WHEN TRY_CAST(b.",k," AS DOUBLE)=t.",m," THEN 'match' ELSE 'mismatch' END,FALSE FROM boxscorelab_team_game_results b LEFT JOIN _bsl_map m ON b.team=m.abbreviation LEFT JOIN _bsl_games l ON b.dataset_id=l.dataset_id AND b.source_row=l.source_row LEFT JOIN historical_team_boxes t ON l.game_id=t.game_id AND 'nba:'||m.nba_id=t.team_id"))
  }
  z<-DBI::dbGetQuery(con,'SELECT season,metric,status,count(*) checks FROM boxscorelab_reconciliation GROUP BY season,metric,status ORDER BY season,metric,status')
  utils::write.csv(z,file.path(directory,'boxscorelab_reconciliation.csv'),row.names=FALSE)
  coverage<-DBI::dbGetQuery(con,"WITH s AS (SELECT season,count(*) team_rows,sum(TRY_CAST(wins AS INTEGER)) wins,sum(TRY_CAST(losses AS INTEGER)) losses,sum(TRY_CAST(games AS INTEGER))/2 claimed_games,bool_and(validation_status='observed') individual_standings_pass FROM boxscorelab_team_standings GROUP BY season), g AS (SELECT season,count(*)/2 available_game_pairs,count(*) FILTER(WHERE validation_status='failed_validation') invalid_team_game_rows FROM boxscorelab_team_game_results GROUP BY season), p AS (SELECT season,count(*) player_season_rows FROM boxscorelab_player_season_totals GROUP BY season) SELECT *,s.wins=s.losses AND s.individual_standings_pass league_standings_consistent,'publisher NBA-derived season totals; no complete independent league denominator certified' limitation FROM s JOIN g USING(season) JOIN p USING(season) ORDER BY season")
  utils::write.csv(coverage,file.path(directory,'boxscorelab_season_coverage.csv'),row.names=FALSE)
  for(t in c('boxscorelab_team_game_results','boxscorelab_team_standings','boxscorelab_player_season_totals')) {
    q<-DBI::dbGetQuery(con,paste0("SELECT '",t,"' AS family,season,provider_key,validation_status FROM ",t," WHERE validation_status!='observed'"))
    utils::write.csv(q,file.path(directory,paste0(t,'_exceptions.csv')),row.names=FALSE)
  }
  invisible(coverage)
}
