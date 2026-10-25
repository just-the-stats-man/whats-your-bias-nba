source('scripts/load.R');con<-phase3_snapshot_connection()
tryCatch({
  snapshots<-DBI::dbReadTable(con,'historical_snapshots')
  snapshots$actual_sha256<-vapply(snapshots$path,file_sha256,character(1));snapshots$passed<-snapshots$sha256==snapshots$actual_sha256
  stopifnot(all(snapshots$passed));utils::write.csv(snapshots,'data/processed/phase3/nba_raw_hashes.csv',row.names=FALSE)
  paths<-list.files('data/processed/historical_parquet',pattern='[.]parquet$',full.names=TRUE)
  out<-data.frame(path=paths,sha256=vapply(paths,file_sha256,character(1)))
  rownames(out)<-NULL
  target<-'data/processed/phase3/nba_normalized_hashes.csv'
  if(file.exists(target))stopifnot(identical(utils::read.csv(target),out)) else utils::write.csv(out,target,row.names=FALSE)
  cat(nrow(snapshots),'NBA raw hashes;',nrow(out),'frozen normalized files verified\n')
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
