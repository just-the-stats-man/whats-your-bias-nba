sdv_effective_version <- function(season) {
  base<-sdv_history_version()
  if(!season_end(season)%in%c(1999L,2000L))return(base)
  substr(digest::digest(list(base,body(ingest_sdv_mixed_calendar)),algo='sha256'),1,16)
}

ingest_sdv_mixed_calendar <- function(con,season) {
  version<-sdv_effective_version(season);end<-season_end(season)
  fn<-ingest_sdv_history;scope<-new.env(parent=environment(fn))
  scope$sdv_history_version<-function()version
  scope$normalize_sdv_history<-function(bundle,season) {
    s<-bundle$schedules$data;date<-as.Date(s$game_date)
    keep<-!is.na(date) & date>=as.Date(sprintf('%d-07-01',end-1L)) & date<=as.Date(sprintf('%d-06-30',end))
    wrong_label<-keep & !is.na(s$season) & s$season!=end
    corrected<-bundle;corrected$schedules$data<-s[keep,,drop=FALSE];corrected$schedules$data$season<-end
    base<-normalize_sdv_history;environment(base)<-scope
    x<-base(corrected,season)
    notes<-attr(x,'normalization_notes')
    raw_id<-paste0('sdv:schedules:',season,':',bundle$schedules$sha256)
    if(any(wrong_label))notes<-rbind(notes,data.frame(game_id=as.character(s$game_id[wrong_label]),rule='season_label_reconstructed_from_unique_pre2015_calendar',detail=paste('recorded date',date[wrong_label],'raw label',s$season[wrong_label],'canonical end year',end),dataset_id=raw_id))
    if(any(!keep))notes<-rbind(notes,data.frame(game_id=as.character(s$game_id[!keep]),rule='cross_season_archive_copy_not_promoted',detail=paste('recorded date',date[!keep],'outside nominal source partition; original bytes retained'),dataset_id=raw_id))
    attr(x,'normalization_notes')<-notes
    x
  }
  environment(fn)<-scope
  fn(con,season)
}
