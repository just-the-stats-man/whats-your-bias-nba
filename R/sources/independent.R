reference_version <- 524L
reference_url <- paste0('https://www.kaggle.com/api/v1/datasets/download/eoinamoore/historical-nba-data-and-player-box-scores/TeamStatistics.csv?datasetVersionNumber=',reference_version)
load_reference_fixture <- function(path='data/sample/independent_team_totals.csv') attach_reference_players(list(data=utils::read.csv(path,stringsAsFactors=FALSE),path=path,url=reference_url,revision='kaggle-v524-filtered-fixture',sha256=file_sha256(path)),path='data/sample/independent_player_rows.csv',download=FALSE)

resolve_reference_version <- function() {
  response<-httr2::request('https://www.kaggle.com/api/v1/datasets/view/eoinamoore/historical-nba-data-and-player-box-scores') |> httr2::req_retry(max_tries=4) |> httr2::req_perform()
  metadata<-httr2::resp_body_json(response)
  if(!identical(metadata$licenseName,'CC0: Public Domain'))stop('Independent source license changed or is unavailable; ingestion disabled for review')
  version<-as.integer(metadata$currentVersionNumber)
  dir.create('data/raw/independent',recursive=TRUE,showWarnings=FALSE)
  jsonlite::write_json(metadata,paste0('data/raw/independent/kaggle_metadata_',version,'.json'),auto_unbox=TRUE,pretty=TRUE)
  version
}

fetch_independent_totals <- function(path=NULL,version=reference_version) {
  if(is.null(path))path<-paste0('data/raw/independent/TeamStatistics_v',version,'.csv')
  url<-paste0('https://www.kaggle.com/api/v1/datasets/download/eoinamoore/historical-nba-data-and-player-box-scores/TeamStatistics.csv?datasetVersionNumber=',as.integer(version))
  if(!file.exists(path)) {
    dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE)
    response<-httr2::request(url) |> httr2::req_timeout(180) |> httr2::req_retry(max_tries=4) |> httr2::req_perform()
    tmp<-tempfile(tmpdir=dirname(path));on.exit(unlink(tmp),add=TRUE)
    writeBin(httr2::resp_body_raw(response),tmp)
    probe<-readLines(tmp,n=1,warn=FALSE)
    if(!startsWith(probe,'gameId,'))stop('Independent source returned an unexpected schema/content type')
    if(!file.rename(tmp,path))stop('Unable to preserve independent source file')
  }
  data<-utils::read.csv(path,stringsAsFactors=FALSE,check.names=FALSE)
  required<-c('gameId','gameDateTimeEst','teamId','opponentTeamId','home','teamScore','fieldGoalsMade','fieldGoalsAttempted','threePointersMade','threePointersAttempted','freeThrowsMade','freeThrowsAttempted','assists','turnovers')
  require_fields(data,required,'Kaggle TeamStatistics')
  attach_reference_players(list(data=data,path=path,url=url,revision=paste0('kaggle-v',as.integer(version)),sha256=file_sha256(path)),version=version)
}

normalize_reference <- function(item,years=2016:2027) {
  d<-item$data
  id<-sprintf('%010.0f',as.numeric(d$gameId))
  endyear<-2001L+as.integer(substr(id,4,5))
  keep<-substr(id,1,3)%in%c('002','004','005','006') & endyear%in%years & !is.na(d$teamScore) & d$teamScore>0
  d<-d[keep,,drop=FALSE];id<-id[keep];endyear<-endyear[keep]
  map<-utils::read.csv('config/team_crosswalk.csv',colClasses='character')
  team<-paste0('espn:',map$espn_id[match(as.character(d$teamId),map$nba_id)])
  opponent<-paste0('espn:',map$espn_id[match(as.character(d$opponentTeamId),map$nba_id)])
  if(any(grepl('NA$',team)) || any(grepl('NA$',opponent)))stop('Independent source has an unmapped NBA franchise')
  out<-data.frame(source_id='eoin_moore_nba',source_game_id=id,season=season_label(endyear),game_date=as.Date(substr(d$gameDateTimeEst,1,10)),team_id=team,opponent_team_id=opponent,home=as.logical(d$home),points=as.integer(d$teamScore),fgm=as.integer(d$fieldGoalsMade),fga=as.integer(d$fieldGoalsAttempted),fg3m=as.integer(d$threePointersMade),fg3a=as.integer(d$threePointersAttempted),ftm=as.integer(d$freeThrowsMade),fta=as.integer(d$freeThrowsAttempted),assists=as.integer(d$assists),turnovers=as.integer(d$turnovers),dataset_id=paste0('kaggle:team:',item$revision,':',item$sha256))
  if(is.null(item$player_totals))stop('Independent player records are required to disambiguate turnover definitions')
  key<-paste(item$player_totals$source_game_id,item$player_totals$nba_team_id)
  idx<-match(paste(id,as.character(d$teamId)),key)
  out$reported_turnovers<-out$turnovers
  out$turnovers<-as.integer(item$player_totals$player_turnovers[idx])
  out$mapped_player_team_rows<-as.integer(item$player_totals$mapped_team_rows[idx])
  out$reference_player_rows<-as.integer(item$player_totals$player_rows[idx])
  out$total_turnovers<-if('turnoversTeam'%in%names(d))as.integer(out$turnovers+d$turnoversTeam) else NA_integer_
  out$dataset_id<-paste0('kaggle:team_player_v2:',item$revision,':',item$sha256,':',item$player_sha256,':',item$player_transform_id)
  deduplicate(out,c('source_id','source_game_id','team_id'))
}

import_reference <- function(con,item=fetch_independent_totals()) {
  d<-normalize_reference(item)
  DBI::dbWithTransaction(con,{
    DBI::dbExecute(con,"INSERT OR IGNORE INTO sources VALUES ('eoin_moore_nba','https://www.kaggle.com/datasets/eoinamoore/historical-nba-data-and-player-box-scores','CC0-1.0 publisher declaration','Eoin Moore; NBA.com upstream; v524 TeamStatistics')")
    raw_team_id<-paste0('kaggle:raw_team:',item$revision,':',item$sha256)
    raw_player_id<-paste0('kaggle:raw_players:',item$revision,':',item$player_sha256)
    directory<-'data/processed/reference';dir.create(directory,recursive=TRUE,showWarnings=FALSE)
    normalized_path<-file.path(directory,paste0('team_player_',substr(item$sha256,1,12),'_',substr(item$player_sha256,1,12),'_',item$player_transform_id,'.parquet'))
    arrow::write_parquet(d,normalized_path)
    manifest<-data.frame(dataset_id=c(raw_team_id,raw_player_id,unique(d$dataset_id)),source_id='eoin_moore_nba',url=c(item$url,item$player_url,item$url),revision=item$revision,retrieved_at=c(file.info(item$path)$mtime,file.info(item$player_path)$mtime,Sys.time()),sha256=c(item$sha256,item$player_sha256,file_sha256(normalized_path)),raw_path=c(item$path,item$player_path,normalized_path),row_count=c(nrow(item$data),item$player_row_count,nrow(d)))
    upsert_rows(con,'datasets',manifest,'dataset_id')
    dependencies<-data.frame(dataset_id=unique(d$dataset_id),parent_dataset_id=c(raw_team_id,raw_player_id),transformation='Observed player turnover sums; missing team IDs require unique same-provider game/home/team/opponent metadata; v2')
    upsert_rows(con,'dataset_dependencies',dependencies,c('dataset_id','parent_dataset_id'))
    # A selected snapshot replaces the normalized reference scope. Preserve
    # old raw/manifests, but never silently retain a withdrawn reference row.
    for(season in season_label(2016:2027))DBI::dbExecute(con,'DELETE FROM independent_team_totals WHERE source_id=? AND season=?',params=list('eoin_moore_nba',season))
    upsert_rows(con,'independent_team_totals',d,c('source_id','source_game_id','team_id'))
  })
  invisible(nrow(d))
}
