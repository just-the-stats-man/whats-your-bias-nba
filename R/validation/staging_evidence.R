staging_enrichment_integrity <- function(con) {
  files<-DBI::dbGetQuery(con,'SELECT DISTINCT staging_artifact_path path,staging_artifact_sha256 sha256 FROM phase4_noncertified_shot_enrichments')
  good<-vapply(files$path,file_sha256,character(1))==files$sha256
  duplicates<-DBI::dbGetQuery(con,'SELECT count(*) n FROM (SELECT dataset_id,source_row FROM phase4_noncertified_shot_enrichments GROUP BY ALL HAVING count(*)!=1)')$n
  invalid<-DBI::dbGetQuery(con,"SELECT count(*) n FROM phase4_noncertified_shot_enrichments WHERE points_attempted IS NULL OR points_attempted NOT IN (2,3) OR certification_status!='noncertified'")$n
  out<-data.frame(check=c('noncertified_derivation_artifact_hashes','noncertified_derivation_version_key','noncertified_derivation_value_status'),violations=c(sum(!good),duplicates,invalid));out$passed<-out$violations==0
  attr(out,'artifact_count')<-nrow(files);out
}
