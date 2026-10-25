withr::local_dir(Sys.getenv('WYB_ROOT'))
testthat::test_that('calendar repair is limited to the two mixed archive partitions', {
  testthat::expect_equal(sdv_effective_version('2003-04'),sdv_history_version())
  testthat::expect_false(sdv_effective_version('1998-99')==sdv_history_version())
  testthat::expect_false(sdv_effective_version('1999-00')==sdv_history_version())
})
