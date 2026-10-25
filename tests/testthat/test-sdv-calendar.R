withr::local_dir(Sys.getenv('WYB_ROOT'))
testthat::test_that('calendar repair is limited to the two mixed archive partitions', {
  original<-substr(digest::digest(list(body(sdv_attempt_features),body(normalize_sdv_history),body(sdv_box_quality),body(ingest_sdv_history),body(quality_report),reconstruction_version),algo='sha256'),1,16)
  testthat::expect_equal(sdv_history_version(),original)
  testthat::expect_equal(sdv_effective_version('2003-04'),sdv_history_version())
  testthat::expect_false(sdv_effective_version('1998-99')==sdv_history_version())
  testthat::expect_false(sdv_effective_version('1999-00')==sdv_history_version())
})
