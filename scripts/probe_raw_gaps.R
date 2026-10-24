# Optional recovery audit. This reads only licensed publisher archives, never
# ESPN/NBA endpoints, and preserves every downloaded JSON byte sequence.
source('scripts/load.R')
revision<-'e2c40720c72a98f427f8964deba8dd0e22ff1303'
root<-file.path('data/raw/sportsdataverse_raw',revision)
dir.create(root,recursive=TRUE,showWarnings=FALSE)
records<-list()
for(year in 2016:2027) {
  base<-file.path('data/raw',archive_revision)
  s<-as.data.frame(arrow::read_parquet(file.path(base,paste0('nba_schedule_',year,'.parquet'))))
  present<-as.character(arrow::read_parquet(file.path(base,paste0('play_by_play_',year,'.parquet')),col_select='game_id')$game_id)
  missing<-as.character(s$game_id[eligible_schedule(s) & !as.character(s$game_id)%in%present])
  for(id in missing) {
    path<-file.path(root,paste0(id,'.json'))
    url<-paste0('https://raw.githubusercontent.com/sportsdataverse/hoopR-nba-raw/',revision,'/nba/json/final/',id,'.json')
    record<-tryCatch({
      if(!file.exists(path)) {
        response<-httr2::request(url) |> httr2::req_timeout(30) |> httr2::req_retry(max_tries=3) |> httr2::req_perform()
        bytes<-httr2::resp_body_raw(response);jsonlite::fromJSON(rawToChar(bytes),simplifyVector=FALSE)
        writeBin(bytes,path);Sys.sleep(.25)
      }
      d<-jsonlite::fromJSON(path,simplifyVector=FALSE)
      data.frame(season=season_label(year),game_id=id,url=url,sha256=file_sha256(path),raw_plays=length(d$plays),status=if(length(d$plays))'alternate_raw_events_available' else 'raw_also_missing_events',detail='')
    },error=function(e)data.frame(season=season_label(year),game_id=id,url=url,sha256=NA_character_,raw_plays=NA_integer_,status='unavailable',detail=conditionMessage(e)))
    records[[length(records)+1L]]<-record
    message(id,': ',record$status)
  }
}
dir.create('data/processed/reports',recursive=TRUE,showWarnings=FALSE)
if(length(records))utils::write.csv(do.call(rbind,records),'data/processed/reports/raw_gap_probes.csv',row.names=FALSE)
