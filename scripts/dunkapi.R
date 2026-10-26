# No request is sent unless the user has separately approved this exact budget.
source('scripts/load.R');args<-commandArgs(trailingOnly=TRUE)
if(length(args)<1L)stop('Usage: Rscript scripts/dunkapi.R GAME_ID [OFFSET]')
approval_path<-Sys.getenv('DUNKAPI_APPROVAL_FILE')
if(!nzchar(approval_path)||!file.exists(approval_path))stop('A private, explicitly approved DUNKAPI_APPROVAL_FILE is required; no request sent')
approval<-jsonlite::fromJSON(approval_path,simplifyVector=TRUE)
params<-list(game_id=args[1],limit=1000L)
if(length(args)>1L) {offset<-suppressWarnings(as.integer(args[2]));if(is.na(offset)||offset<0L)stop('Invalid offset');params$offset<-offset}
receipt<-dunkapi_fetch('get_plays',params,approval=approval)
con<-connect_warehouse()
tryCatch({rows<-ingest_dunkapi_snapshot(con,receipt);cat('Stored source observations:',nrow(rows),'response SHA-256:',receipt$sha256,'\n')},finally=DBI::dbDisconnect(con,shutdown=TRUE))
