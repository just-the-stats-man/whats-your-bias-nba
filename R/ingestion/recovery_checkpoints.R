# Cache plumbing is separate from certification method versions. Incidental
# R row names / diagnostic attributes must not invalidate identical evidence.
terminal_checkpoint_key <- function(candidates,events,box,reference,terminal,method) {
  frames<-list(candidates,events,box,reference,terminal)
  for(i in seq_along(frames)) {
    x<-frames[[i]];attr(x,'player_links')<-NULL;rownames(x)<-NULL;frames[[i]]<-x
  }
  digest::digest(c(frames,list(method)),algo='sha256')
}

verify_frozen_phase3_inputs <- function(con) {
  expected<-utils::read.csv('data/processed/phase4/baseline_tables.csv',colClasses=c(table='character',n='numeric',checksum='character'));path<-'data/processed/phase4/frozen_input_verification.rds'
  file<-file.info('data/processed/phase4/baseline.duckdb');identity<-list(manifest=file_sha256('data/processed/phase4/baseline_tables.csv'),size=file$size,mtime=file$mtime)
  if(file.exists(path)&&identical(readRDS(path)$identity,identity))return(invisible(identity))
  for(i in seq_len(nrow(expected))) {
    q<-paste0('SELECT count(*) n,CAST(bit_xor(hash(x)) AS VARCHAR) checksum FROM baseline.main.',DBI::dbQuoteIdentifier(con,expected$table[i]),' x')
    actual<-DBI::dbGetQuery(con,q)
    stopifnot(actual$n==expected$n[i],identical(actual$checksum,expected$checksum[i]))
  }
  saveRDS(list(identity=identity,verified_at=Sys.time()),path);invisible(identity)
}
