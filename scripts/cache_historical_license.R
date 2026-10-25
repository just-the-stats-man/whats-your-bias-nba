# Capture the publisher's license declaration before downloading pinned files.
source('scripts/load.R')
version<-524L
path<-paste0('data/raw/independent/kaggle_metadata_',version,'.json')
if(!file.exists(path)) {
  dir.create(dirname(path),recursive=TRUE,showWarnings=FALSE)
  url<-paste0('https://www.kaggle.com/api/v1/datasets/view/eoinamoore/historical-nba-data-and-player-box-scores?datasetVersionNumber=',version)
  response<-httr2::request(url) |> httr2::req_timeout(120) |> httr2::req_retry(max_tries=3) |> httr2::req_perform()
  meta<-httr2::resp_body_json(response)
  if(!identical(meta$licenseName,'CC0: Public Domain'))stop('Publisher license changed or unavailable: historical download disabled for review')
  writeBin(httr2::resp_body_raw(response),path)
  jsonlite::write_json(list(url=url,requested_version=version,metadata_current_version=meta$currentVersionNumber,reviewed_at=format(Sys.time(),tz='UTC',usetz=TRUE),sha256=file_sha256(path)),paste0(path,'.receipt.json'),auto_unbox=TRUE,pretty=TRUE)
}
stopifnot(jsonlite::read_json(path)$licenseName=='CC0: Public Domain')
cat('Publisher license snapshot:',path,'SHA256',file_sha256(path),'\n')
