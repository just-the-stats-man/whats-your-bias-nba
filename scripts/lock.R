source('scripts/load.R')
options(repos=c(CRAN='https://cloud.r-project.org'))
renv::snapshot(lockfile='renv.lock',packages=c('DBI','duckdb','arrow','bit64','dplyr','dbplyr','httr2','jsonlite','digest','targets','renv','testthat','withr','knitr','rmarkdown'),prompt=FALSE)
