# Bootstrap renv locally; restore the exact lockfile without paid credentials.
dir.create('.library',showWarnings=FALSE)
.libPaths(c(normalizePath('.library'),.libPaths()))
options(repos=c(CRAN='https://cloud.r-project.org'))
if (!requireNamespace('renv',quietly=TRUE)) install.packages('renv',lib='.library')
renv::restore(lockfile='renv.lock',library=normalizePath('.library'),prompt=FALSE)
