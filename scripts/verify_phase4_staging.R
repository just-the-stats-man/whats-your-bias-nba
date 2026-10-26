# Supplement a completed full verification without rehashing unchanged raw
# history when only the additional staging-evidence checks are introduced.
source('scripts/load.R');con<-DBI::dbConnect(duckdb::duckdb(),dbdir='data/processed/nba.duckdb',read_only=TRUE)
tryCatch({
  extra<-staging_enrichment_integrity(con);old<-utils::read.csv('docs/phase4/final_integrity.csv')
  all<-rbind(old[!old$check%in%extra$check,],extra);stopifnot(all(all$passed))
  utils::write.csv(all,'docs/phase4/final_integrity.csv',row.names=FALSE)
  cat(nrow(all),'total checks passed;',attr(extra,'artifact_count'),'noncertified derivation artifact hashes verified\n')
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
