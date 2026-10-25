fetch_sdv_history <- function(season,revision=archive_revision) {
  year<-season_end(season)
  if(year<1994L || year>2027L)stop('Season absent from pinned SDV inventory')
  specs<-c(schedules='nba_schedule',player_box='player_box',team_box='team_box',pbp='play_by_play')
  if(year<2002L)specs<-specs[names(specs)!='pbp']
  out<-lapply(names(specs),function(kind) {
    name<-paste0(specs[[kind]],'_',year,'.parquet')
    path<-file.path('data/raw',revision,name)
    url<-sprintf('https://raw.githubusercontent.com/sportsdataverse/hoopR-nba-data/%s/nba/%s/parquet/%s',revision,kind,name)
    fetch_cached(url,path)
    list(data=as.data.frame(arrow::read_parquet(path)),path=path,url=url,revision=revision,sha256=file_sha256(path))
  })
  stats::setNames(out,names(specs))
}

register_sdv_history_raw <- function(con,bundle,season) {
  DBI::dbExecute(con,"INSERT OR IGNORE INTO sources VALUES ('sportsdataverse','https://github.com/sportsdataverse/hoopR-nba-data','CC-BY-4.0','hoopR authors; ESPN upstream')")
  rows<-do.call(rbind,lapply(names(bundle),function(k) {
    z<-bundle[[k]]
    data.frame(dataset_id=paste0('sdv:',k,':',season,':',z$sha256),source_id='sportsdataverse',url=z$url,revision=z$revision,retrieved_at=file.info(z$path)$mtime,sha256=z$sha256,raw_path=z$path,row_count=nrow(z$data))
  }))
  # Do not rewrite metadata for a raw snapshot already registered.
  existing<-DBI::dbGetQuery(con,'SELECT dataset_id FROM datasets')$dataset_id
  upsert_rows(con,'datasets',rows[!rows$dataset_id%in%existing,,drop=FALSE],'dataset_id')
  invisible(rows)
}
