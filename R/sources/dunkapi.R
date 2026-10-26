dunkapi_cost <- function(endpoint) {
  costs<-c(list_teams=1,search_players=1,list_games=2,get_game=5,get_plays=10,get_shot_chart=10)
  if(length(endpoint)!=1L || !endpoint%in%names(costs))stop('Unsupported DunkAPI endpoint')
  unname(costs[endpoint])
}

dunkapi_transport <- function(url,key,params) {
  req<-httr2::request(url) |> httr2::req_headers(`x-api-key`=key) |> httr2::req_body_json(params) |> httr2::req_timeout(45) |> httr2::req_error(is_error=function(resp)FALSE)
  resp<-httr2::req_perform(req)
  list(status=httr2::resp_status(resp),body=httr2::resp_body_raw(resp))
}

# Merely configuring a key never authorizes credit-consuming requests.
# No automatic pagination/retry: each page consumes an explicit local budget.
dunkapi_fetch <- function(endpoint,params=list(),cache_dir='data/raw/authorized/dunkapi',approval=NULL,transport=dunkapi_transport,wait=Sys.sleep,now=Sys.time) {
  cost<-dunkapi_cost(endpoint)
  allowed<-switch(endpoint,get_plays=c('game_id','player_id','team','season','season_type','shots_only','made','zone','period','clutch','limit','offset'),get_shot_chart=c('game_id','player_id','team','opponent','season','season_type','include_shots'),get_game='game_id',list_games=c('season','date','start_date','end_date','team','season_type','limit','offset'),search_players=c('query','name','limit','offset'),list_teams=c('season'))
  if(is.null(names(params)) && length(params) || any(!names(params)%in%allowed) || anyDuplicated(names(params)))stop('Unsupported or duplicate request parameters')
  if(endpoint%in%c('get_game','get_plays','get_shot_chart') && (is.null(params$game_id)||length(params$game_id)!=1L||!is.character(params$game_id)||!grepl('^[0-9]+$',params$game_id)))stop('This targeted adapter requires an explicit numeric game_id string')
  params<-params[order(names(params))]
  request_hash<-digest::digest(list(endpoint,params,'dunkapi-docs-2026-10-25'),algo='sha256')
  dir.create(cache_dir,recursive=TRUE,showWarnings=FALSE);cache_dir<-normalizePath(cache_dir,winslash='/')
  receipt_path<-file.path(cache_dir,paste0('request-',request_hash,'.rds'))
  if(file.exists(receipt_path)) {
    receipt<-readRDS(receipt_path)
    if(file_sha256(receipt$path)!=receipt$sha256)stop('Cached DunkAPI response hash mismatch')
    return(receipt)
  }
  valid<-is.list(approval) && isTRUE(approval$approved) && identical(approval$provider,'dunkapi') && endpoint%in%approval$endpoints && isTRUE(approval$terms_accepted) && length(approval$approval_id)==1L && nzchar(approval$approval_id) && length(approval$max_credits)==1L && is.finite(approval$max_credits) && approval$max_credits>=cost && !is.null(approval$expires_at) && as.POSIXct(approval$expires_at,tz='UTC')>now()
  if(!isTRUE(valid))stop('Explicit, unexpired request/credit approval and accepted terms required; no request sent')
  key<-Sys.getenv('DUNKAPI_API_KEY');if(!nzchar(key))stop('DUNKAPI_API_KEY is not configured; no request sent')
  lock<-file.path(cache_dir,'request.lock')
  if(!dir.create(lock,showWarnings=FALSE))stop('Another DunkAPI request is active; no request sent')
  stopifnot(dirname(normalizePath(lock,winslash='/'))==cache_dir)
  on.exit(unlink(lock,recursive=TRUE),add=TRUE)
  ledger_path<-file.path(cache_dir,paste0('approval-',digest::digest(approval$approval_id,algo='sha256'),'.rds'))
  approval_hash<-digest::digest(approval,algo='sha256')
  ledger<-if(file.exists(ledger_path))readRDS(ledger_path) else list(approval_hash=approval_hash,spent=0,last_request=as.POSIXct(NA))
  if(ledger$approval_hash!=approval_hash)stop('Approval changed; a separately approved ID is required')
  if(ledger$spent+cost>approval$max_credits)stop('Approved credit cap exhausted; no request sent')
  if(!is.na(ledger$last_request)) {
    delay<-6.1-as.numeric(difftime(now(),ledger$last_request,units='secs'));if(delay>0)wait(delay)
  }
  ledger$spent<-ledger$spent+cost;ledger$last_request<-now();saveRDS(ledger,ledger_path)
  # Reserve even failed calls; provider credit refunds are never assumed.
  response<-tryCatch(transport(paste0('https://mcp.dunkapi.com/v1/',endpoint),key,params),error=function(e)stop('DunkAPI transport failed; no automatic retry; local credit reservation retained',call.=FALSE))
  if(!identical(as.integer(response$status),200L))stop('DunkAPI returned a non-success status; no automatic retry or error-body logging')
  bytes<-response$body;if(is.character(bytes))bytes<-charToRaw(bytes)
  if(!is.raw(bytes))stop('Invalid response body type')
  if(grepl(key,rawToChar(bytes),fixed=TRUE))stop('Response contains credential material; it was not cached')
  payload<-tryCatch(jsonlite::fromJSON(rawToChar(bytes),simplifyVector=FALSE),error=function(e)stop('Invalid response JSON; no response body logged'))
  if(endpoint=='get_plays')validate_dunkapi_plays(payload)
  sha<-digest::digest(bytes,algo='sha256',serialize=FALSE);path<-file.path(cache_dir,paste0(sha,'.json'))
  if(!file.exists(path))writeBin(bytes,path)
  receipt<-list(provider='dunkapi',endpoint=endpoint,request_hash=request_hash,params=params,path=path,sha256=sha,received_at=now(),schema_id=paste0('dunkapi-',endpoint,'-docs-2026-10-25'),terms_url='https://dunkapi.com/terms',permission_status='approved_internal_use_no_raw_redistribution',approval_id=approval$approval_id,live_validated=identical(transport,dunkapi_transport))
  saveRDS(receipt,receipt_path);receipt
}

validate_dunkapi_plays <- function(payload) {
  if(!is.list(payload)||!'plays'%in%names(payload)||!is.list(payload$plays)||!is.numeric(payload$count)||length(payload$count)!=1L||payload$count!=length(payload$plays))stop('Unsupported get_plays response schema/count')
  if(!is.null(payload$next_offset) && (length(payload$next_offset)!=1L||!is.numeric(payload$next_offset)||!is.finite(payload$next_offset)||payload$next_offset<0))stop('Invalid pagination offset')
  for(p in payload$plays)if(!is.list(p)||!all(c('game_id','seq','period','clock_seconds','type','text')%in%names(p))||(!is.null(p$shot)&&!is.list(p$shot)))stop('Unsupported get_plays event schema')
  invisible(TRUE)
}

normalize_dunkapi_plays <- function(payload,sha) {
  validate_dunkapi_plays(payload)
  scalar<-function(x,type='character') {
    if(is.null(x))return(switch(type,character=NA_character_,numeric=NA_real_,logical=NA))
    if(length(x)!=1L || !switch(type,character=is.character(x),numeric=is.numeric(x),logical=is.logical(x)))return(switch(type,character=NA_character_,numeric=NA_real_,logical=NA))
    x
  }
  out<-lapply(seq_along(payload$plays),function(i){
    p<-payload$plays[[i]];s<-p$shot
    type<-scalar(p$type);value<-scalar(s$points_attempted,'numeric');ft<-grepl('free[ _-]*throw',tolower(type))
    unit<-if(is.null(s))'non_shot_event' else if(ft)'free_throw' else if(value%in%c(2,3))'field_goal' else 'unknown_shot'
    period<-scalar(p$period,'numeric');clock<-scalar(p$clock_seconds,'numeric');seq<-scalar(p$seq,'numeric')
    invalid<-is.na(period)||period<1||period!=floor(period)||is.na(clock)||clock<0||clock>ifelse(period<=4,720,300)||is.na(seq)||seq<0||seq!=floor(seq)||is.na(type)||is.na(scalar(p$game_id))||(ft&&!is.na(value)&&value!=1)
    data.frame(snapshot_sha256=sha,source_row=i,native_game_id=scalar(p$game_id),native_sequence=seq,period=period,clock_seconds=clock,native_team=scalar(p$team),native_player_id=scalar(p$player_id),native_secondary_player_id=scalar(p$player2_id),event_type=type,description=scalar(p$text),shot_class=unit,made=scalar(s$made,'logical'),points_attempted=value,raw_x=scalar(s$x,'numeric'),raw_y=scalar(s$y,'numeric'),expected_points=scalar(s$expected_points,'numeric'),home_win_probability=scalar(p$home_win_prob,'numeric'),coordinate_status=if(is.null(s$x)||is.null(s$y))'source_missing' else 'source_frame_unverified',model_status=if(is.null(s$expected_points)&&is.null(p$home_win_prob))'source_missing' else 'estimated',validation_status=if(invalid)'failed_validation' else 'observed_provider_record',independent=FALSE,raw_record_json=as.character(jsonlite::toJSON(p,auto_unbox=TRUE,null='null',digits=NA)),stringsAsFactors=FALSE)
  })
  if(!length(out))return(data.frame())
  out<-do.call(rbind,out);key<-paste(out$native_game_id,out$native_sequence);dup<-duplicated(key)|duplicated(key,fromLast=TRUE);out$validation_status[dup]<-'failed_validation';out
}
