reference_version <- 524L
reference_url <- paste0('https://www.kaggle.com/api/v1/datasets/download/eoinamoore/historical-nba-data-and-player-box-scores/TeamStatistics.csv?datasetVersionNumber=',reference_version)
load_reference_fixture <- function(path='data/sample/independent_team_totals.csv') list(data=utils::read.csv(path,stringsAsFactors=FALSE),path=path,url=reference_url,revision='kaggle-v524-filtered-fixture',sha256=file_sha256(path))

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
  list(data=data,path=path,url=url,revision=paste0('kaggle-v',as.integer(version)),sha256=file_sha256(path))
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
  out$total_turnovers<-if('turnoversTeam'%in%names(d))as.integer(d$turnovers+d$turnoversTeam) else NA_integer_
  deduplicate(out,c('source_id','source_game_id','team_id'))
}

import_reference <- function(con,item=fetch_independent_totals()) {
  d<-normalize_reference(item)
  DBI::dbWithTransaction(con,{
    DBI::dbExecute(con,"INSERT OR IGNORE INTO sources VALUES ('eoin_moore_nba','https://www.kaggle.com/datasets/eoinamoore/historical-nba-data-and-player-box-scores','CC0-1.0 publisher declaration','Eoin Moore; NBA.com upstream; v524 TeamStatistics')")
    manifest<-data.frame(dataset_id=unique(d$dataset_id),source_id='eoin_moore_nba',url=item$url,revision=item$revision,retrieved_at=file.info(item$path)$mtime,sha256=item$sha256,raw_path=item$path,row_count=nrow(item$data))
    upsert_rows(con,'datasets',manifest,'dataset_id')
    upsert_rows(con,'independent_team_totals',d,c('source_id','source_game_id','team_id'))
  })
  invisible(nrow(d))
}
