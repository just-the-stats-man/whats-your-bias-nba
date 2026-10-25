source('scripts/load.R')
save_once<-function(url,path) {
  if(file.exists(path))return(invisible(path))
  dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE)
  temp<-paste0(path,'.partial')
  on.exit(if(file.exists(temp))unlink(temp),add=TRUE)
  httr2::request(url) |> httr2::req_timeout(300) |> httr2::req_retry(max_tries=3) |> httr2::req_perform(path=temp)
  if(!file.rename(temp,path))stop('Cache publication failed')
  invisible(path)
}
metadata<-'data/raw/tracking/shot_features_metadata_v1.json'
save_once('https://www.kaggle.com/api/v1/datasets/view/juanmaoliver/shot-features',metadata)
m<-jsonlite::read_json(metadata)
if(m$licenseName!='MIT' || m$currentVersionNumber!=1L)stop('Pinned v1 dataset license unavailable; review before retrieving another release')
save_once('https://www.kaggle.com/api/v1/datasets/download/juanmaoliver/shot-features/shot_features.csv?datasetVersionNumber=1','data/raw/tracking/shot_features_v1.csv')
stopifnot(file.info('data/raw/tracking/shot_features_v1.csv')$size==m$totalBytes)
folder<-'data/raw/boxscorelab/build-20261025T1216'
paths<-file.path(folder,unlist(lapply(season_label(2023:2027),function(s)paste0(s,'-',c('player-season-totals','team-standings','team-game-results'),'.csv'))))
save_once('https://boxscorelab.com/downloads/',file.path(folder,'downloads.html'))
receipt<-paste(readLines(file.path(folder,'downloads.html'),warn=FALSE),collapse='\n')
if(!grepl('CC BY 4.0',receipt,fixed=TRUE) || !grepl('20261025T1216',receipt,fixed=TRUE))stop('Expected licensed BoxScore Lab build receipt unavailable')
if(any(!file.exists(paths))) {
  # CSV URLs change nightly; the original build cannot be recreated from a
  # later build merely by reusing its directory name.
  before<-httr2::request('https://boxscorelab.com/downloads/') |> httr2::req_perform() |> httr2::resp_body_string()
  if(!grepl('20261025T1216',before,fixed=TRUE))stop('Publisher has moved past this build; retain original cache or review a new version')
  for(path in paths)save_once(paste0('https://boxscorelab.com/downloads/',basename(path)),path)
  after<-httr2::request('https://boxscorelab.com/downloads/') |> httr2::req_perform() |> httr2::resp_body_string()
  if(!grepl('20261025T1216',after,fixed=TRUE))stop('Publisher build changed during download; do not ingest this unverified cache')
}
save_once('https://boxscorelab.com/methodology/',file.path(folder,'methodology.html'))
cat('Supplementary source caches available; no existing files replaced\n')
