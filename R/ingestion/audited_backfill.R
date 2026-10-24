reconstruction_version <- paste0('pl-v1-',substr(digest::digest(lapply(c('R/analysis/reconstruction.R','R/ingestion/reconstruct_warehouse.R','R/validation/reconciliation.R','R/cleaning/normalize.R'),readLines,warn=FALSE),algo='sha256'),1,12))

slice_games <- function(x,ids) {
  out<-lapply(x,function(d) if('game_id' %in% names(d)) d[d$game_id %in% ids,,drop=FALSE] else d)
  out$players<-out$players[out$players$player_id%in%out$player_box_scores$player_id,,drop=FALSE]
  out$player_identifiers<-out$player_identifiers[out$player_identifiers$player_id%in%out$player_box_scores$player_id,,drop=FALSE]
  out
}

exception_rows <- function(game_id,season,stage,rule,detail,severity='error',dataset_id=NA_character_) {
  n <- max(length(game_id),length(rule),length(detail))
  d <- data.frame(game_id=rep_len(game_id,n),season=rep_len(season,n),stage=rep_len(stage,n),severity=rep_len(severity,n),rule=rep_len(rule,n),detail=rep_len(detail,n),dataset_id=rep_len(dataset_id,n),version=reconstruction_version,stringsAsFactors=FALSE)
  d$exception_id <- vapply(seq_len(n),function(i)digest::digest(paste(d[i,],collapse='|'),algo='sha256'),character(1))
  unique(d[,c('exception_id',setdiff(names(d),'exception_id'))])
}

audit_ingest_season <- function(con,season,revision=archive_revision) {
  bundle <- fetch_season(season,revision)
  bundle <- lapply(bundle,function(z){z$sha256<-file_sha256(z$path);z})
  s<-bundle$schedules$data;s<-s[eligible_schedule(s),,drop=FALSE]
  inventory<-data.frame(game_id=as.character(s$game_id),season=season,game_date=as.Date(s$game_date),home_team_id=provider_id(s$home_id),away_team_id=provider_id(s$away_id),has_player_box=as.character(s$game_id)%in%as.character(bundle$player_box$data$game_id),has_team_box=as.character(s$game_id)%in%as.character(bundle$team_box$data$game_id),has_pbp=as.character(s$game_id)%in%as.character(bundle$pbp$data$game_id),validation_status='pending',dataset_id=paste0('sdv:schedules:',season,':',bundle$schedules$sha256))
  upsert_rows(con,'schedule_inventory',inventory,'game_id')
  x <- normalize_bundle(bundle,season)
  notes<-attr(x,'normalization_notes')
  if(!is.null(notes) && nrow(notes))upsert_rows(con,'quality_exceptions',exception_rows(notes$game_id,season,'normalization',notes$rule,notes$detail,severity='warning',dataset_id=notes$dataset_id),'exception_id')
  DBI::dbExecute(con,"INSERT OR IGNORE INTO sources VALUES ('sportsdataverse','https://github.com/sportsdataverse/hoopR-nba-data','CC-BY-4.0','hoopR.nba authors; ESPN upstream; normalized by Whats Your Bias')")
  manifests <- do.call(rbind,lapply(names(bundle),function(k) {
    z<-bundle[[k]]
    data.frame(dataset_id=paste0('sdv:',k,':',season,':',z$sha256),source_id='sportsdataverse',url=z$url,revision=z$revision,retrieved_at=file.info(z$path)$mtime,sha256=z$sha256,raw_path=z$path,row_count=nrow(z$data))
  }))
  upsert_rows(con,'datasets',manifests,'dataset_id')
  # Partition once. Full raw files and their manifests survive quarantining.
  indices <- lapply(x,function(d) if('game_id' %in% names(d)) split(seq_len(nrow(d)),d$game_id) else NULL)
  valid <- character(); failures<-list()
  for(id in x$games$game_id) {
    one <- lapply(names(x),function(k) if(is.null(indices[[k]])) x[[k]] else x[[k]][indices[[k]][[id]],,drop=FALSE])
    names(one)<-names(x)
    one$players<-one$players[one$players$player_id%in%one$player_box_scores$player_id,,drop=FALSE]
    one$player_identifiers<-one$player_identifiers[one$player_identifiers$player_id%in%one$player_box_scores$player_id,,drop=FALSE]
    r <- tryCatch(quality_report(one),error=function(e)data.frame(check='validator failure',severity='error',count=1L,detail=conditionMessage(e)))
    if(nrow(r)) {
      failures[[length(failures)+1L]]<-exception_rows(id,season,'ingestion',r$check,paste('affected records:',r$count),r$severity,one$games$dataset_id[1])
    }
    if(!any(r$severity=='error')) valid<-c(valid,id)
  }
  if(length(failures)) upsert_rows(con,'quality_exceptions',do.call(rbind,failures),'exception_id')
  inventory$validation_status<-ifelse(inventory$game_id%in%valid,'passed','quarantined')
  upsert_rows(con,'schedule_inventory',inventory,'game_id')
  # Re-import every valid source snapshot: starters and additional actor fields
  # must be populated even for games imported by the initial milestone.
  for(ids in split(valid,ceiling(seq_along(valid)/250))) {
    ingest_bundle(con,bundle,season,normalized=slice_games(x,ids),validated_report=data.frame(check=character(),severity=character(),count=integer()))
  }
  message(season,': ',length(valid),' / ',nrow(x$games),' eligible games passed; ',nrow(x$games)-length(valid),' quarantined')
  invisible(list(eligible=nrow(x$games),passed=length(valid)))
}
