source('scripts/load.R')
Sys.setenv(WYB_ROOT=normalizePath('.'))
testthat::test_dir('tests/testthat',stop_on_failure=TRUE)
