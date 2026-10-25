# This is a provider's derived feature release, not raw optical observations.
# Native names remain labels; proximity never creates a defender assignment.
normalize_tracking_features <- function(raw,games,dataset_id) {
  required<-c('game_id','team_id','player_name','closest_def_name','quarter','game_time','made_shot','x','y','dist','closest_def_dist','shot_clock','touch_time')
  stopifnot(all(required%in%names(raw)))
  number<-function(k)suppressWarnings(as.numeric(raw[[k]]))
  gid<-paste0('nba:',sprintf('%010.0f',number('game_id')))
  tid<-paste0('nba:',sprintf('%.0f',number('team_id')))
  j<-match(gid,games$game_id);q<-number('quarter');elapsed<-number('game_time')
  before<-ifelse(q<=4,(q-1)*720,2880+(q-5)*300)
  after<-ifelse(q<=4,q*720,2880+(q-4)*300)
  valid<-!is.na(j) & games$season[j]=='2015-16' & tid%in%c(games$home_team_id,games$away_team_id)
  valid<-valid & (tid==games$home_team_id[j] | tid==games$away_team_id[j]) & q>=1 & q<=20 & q==floor(q) & elapsed>=before-1 & elapsed<=after+1 & number('made_shot')%in%c(0,1)
  valid[is.na(valid)]<-FALSE
  context<-data.frame(dataset_id=dataset_id,source_row=seq_len(nrow(raw)),game_id=gid,season='2015-16',team_id=tid,shooter_name=raw$player_name,nearest_name=raw$closest_def_name,period=q,elapsed_seconds=elapsed,made=number('made_shot')==1,validation_status=ifelse(valid,'estimated','failed_validation'),method='publisher inferred release frame; not independently reproduced',stringsAsFactors=FALSE)
  limits<-list(x=c(-10,104),y=c(-10,60),dist=c(0,110),closest_def_dist=c(0,110),second_closest_def_dist=c(0,110),shot_clock=c(0,24.1),touch_time=c(0,300),shooter_par_vel=c(-100,100),shooter_perp_vel=c(-100,100),def_par_vel=c(-100,100),def_perp_vel=c(-100,100))
  geometry<-abs(sqrt((number('x')-88.75)^2+(number('y')-25)^2)-number('dist'))<=0.25
  estimates<-do.call(rbind,lapply(intersect(names(limits),names(raw)),function(k) {
    value<-number(k);missing<-is.na(value);good<-valid & is.finite(value) & value>=limits[[k]][1] & value<=limits[[k]][2]
    if(k%in%c('x','y','dist'))good<-good & geometry
    good[is.na(good)]<-FALSE
    data.frame(dataset_id=dataset_id,source_row=seq_len(nrow(raw)),metric=k,reported_value=value,value=ifelse(good,value,NA_real_),status=ifelse(missing,'source_missing',ifelse(good,'estimated','failed_validation')),uncertainty=NA_real_,uncertainty_status='source_missing',stringsAsFactors=FALSE)
  }))
  list(context=context,estimates=estimates)
}

ingest_tracking_features <- function(con,path='data/raw/tracking/shot_features_v1.csv',metadata='data/raw/tracking/shot_features_metadata_v1.json',games_path='data/processed/historical_parquet/historical_games.parquet') {
  meta<-jsonlite::read_json(metadata)
  if(meta$licenseName!='MIT' || meta$currentVersionNumber!=1L)stop('Pinned publisher MIT dataset declaration required')
  stopifnot(file.info(path)$size==meta$totalBytes)
  for(p in c(path,metadata)) {
    prior<-DBI::dbGetQuery(con,'SELECT sha256 FROM datasets WHERE raw_path=?',params=list(p))$sha256
    if(length(prior) && any(prior!=file_sha256(p)))stop('Registered tracking input path changed')
  }
  hash<-file_sha256(path);id<-paste0('shot-features:v1:',hash)
  derived<-paste0(id,':',substr(digest::digest(body(normalize_tracking_features),algo='sha256'),1,16))
  DBI::dbExecute(con,'CREATE TABLE IF NOT EXISTS tracking_provider_context (dataset_id VARCHAR,source_row BIGINT,game_id VARCHAR,season VARCHAR,team_id VARCHAR,shooter_name VARCHAR,nearest_name VARCHAR,period INTEGER,elapsed_seconds DOUBLE,made BOOLEAN,validation_status VARCHAR,method VARCHAR,PRIMARY KEY(dataset_id,source_row))')
  DBI::dbExecute(con,'CREATE TABLE IF NOT EXISTS tracking_provider_estimates (dataset_id VARCHAR,source_row BIGINT,metric VARCHAR,reported_value DOUBLE,value DOUBLE,status VARCHAR,uncertainty DOUBLE,uncertainty_status VARCHAR,PRIMARY KEY(dataset_id,source_row,metric))')
  parents<-data.frame(dataset_id=derived,parent_dataset_id=c(id,paste0(id,':metadata')),transformation='Provider-derived release-context normalization; method body fingerprint retained; not raw optical observations')
  if(nrow(DBI::dbGetQuery(con,'SELECT dataset_id FROM datasets WHERE dataset_id=?',params=list(derived)))) {
    upsert_rows(con,'dataset_dependencies',parents,c('dataset_id','parent_dataset_id'))
    return(invisible('unchanged'))
  }
  raw<-utils::read.csv(path,colClasses='character',check.names=FALSE)
  games<-as.data.frame(arrow::read_parquet(games_path,col_select=c('game_id','season','home_team_id','away_team_id')))
  x<-normalize_tracking_features(raw,games,derived)
  url<-'https://www.kaggle.com/datasets/juanmaoliver/shot-features'
  folder<-file.path('data/processed/tracking_features',substr(hash,1,16));dir.create(folder,recursive=TRUE,showWarnings=FALSE)
  DBI::dbWithTransaction(con,{
    upsert_rows(con,'sources',data.frame(source_id='juan_oliver_shot_features',url=url,license='MIT (publisher dataset declaration); no grant inferred for upstream raw trajectories',attribution='Juan Oliver; 2015-16 SportVU/PBP derived feature build; source mirrors acknowledged in metadata'),'source_id')
    register<-function(key,p,n,revision='kaggle-v1')upsert_rows(con,'datasets',data.frame(dataset_id=key,source_id='juan_oliver_shot_features',url=url,revision=revision,retrieved_at=file.info(p)$mtime,sha256=file_sha256(p),raw_path=p,row_count=n),'dataset_id')
    register(id,path,nrow(raw));register(paste0(id,':metadata'),metadata,1)
    for(k in names(x)) {
      out<-file.path(folder,paste0(k,'-',sub('.*:','',derived),'.parquet'));arrow::write_parquet(x[[k]],out)
      key<-paste0(derived,':',k);register(key,out,nrow(x[[k]]),'provider-estimates-v1')
      upsert_rows(con,'dataset_dependencies',data.frame(dataset_id=key,parent_dataset_id=c(id,paste0(id,':metadata')),transformation='Provider release-context estimates; range/identity checks only; no player-name mapping or modeled archetypes'),c('dataset_id','parent_dataset_id'))
      DBI::dbAppendTable(con,paste0('tracking_provider_',k),x[[k]])
    }
    # Checkpoint identity is distinct from the physical normalized family IDs.
    register(derived,path,nrow(raw),'provider-estimates-v1')
    upsert_rows(con,'dataset_dependencies',parents,c('dataset_id','parent_dataset_id'))
  })
  invisible(x$context)
}
