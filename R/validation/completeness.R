refresh_inventory <- function(con,years=2016:2027) {
  root<-file.path('data/raw',archive_revision)
  for(year in years) {
    paths<-file.path(root,paste0(c('nba_schedule','player_box','team_box','play_by_play'),'_',year,'.parquet'))
    if(!all(file.exists(paths)))next
    s<-as.data.frame(arrow::read_parquet(paths[1]));s<-s[eligible_schedule(s),,drop=FALSE]
    ids<-lapply(paths[-1],function(path)as.character(arrow::read_parquet(path,col_select='game_id')$game_id))
    loaded<-DBI::dbGetQuery(con,'SELECT game_id FROM games WHERE season=?',params=list(season_label(year)))$game_id
    competition<-ifelse(s$season_type==5,'play_in',ifelse(s$season_type==3,'playoffs','regular_season'))
    if('notes_headline'%in%names(s))competition[grepl('NBA (Cup|In-Season Tournament) Championship',s$notes_headline)]<-'nba_cup_final'
    inv<-data.frame(game_id=as.character(s$game_id),season=season_label(year),game_date=as.Date(s$game_date),home_team_id=provider_id(s$home_id),away_team_id=provider_id(s$away_id),has_player_box=as.character(s$game_id)%in%ids[[1]],has_team_box=as.character(s$game_id)%in%ids[[2]],has_pbp=as.character(s$game_id)%in%ids[[3]],validation_status=ifelse(as.character(s$game_id)%in%loaded,'passed','quarantined'),dataset_id=paste0('sdv:schedules:',season_label(year),':',file_sha256(paths[1])),competition=competition)
    upsert_rows(con,'schedule_inventory',inv,'game_id')
    DBI::dbExecute(con,'UPDATE games SET competition=i.competition FROM schedule_inventory i WHERE games.game_id=i.game_id')
  }
}

completeness_report <- function(con,years=2016:2027,directory='docs') {
  dir.create(directory,recursive=TRUE,showWarnings=FALSE)
  rows<-list()
  for(year in years) {
    season<-season_label(year)
    count<-function(sql,params=list(season))as.integer(DBI::dbGetQuery(con,sql,params=params)[[1]][1])
    source<-count('SELECT count(*) FROM schedule_inventory WHERE season=?')
    canonical<-count('SELECT count(*) FROM games WHERE season=?')
    ref<-count('SELECT count(*) FROM independent_team_totals WHERE season=? AND home')
    recon<-DBI::dbGetQuery(con,'SELECT * FROM reconstruction_status WHERE season=? AND version=?',params=list(season,reconstruction_version))
    match<-DBI::dbGetQuery(con,'SELECT c.game_id,bool_and(c.passed IS TRUE) passed,bool_or(c.passed IS FALSE) mismatch,bool_or(c.passed IS NULL) unavailable FROM reconciliation_checks c JOIN games g USING(game_id) WHERE g.season=? GROUP BY c.game_id',params=list(season))
    dependent<-count('SELECT count(DISTINCT c.game_id) FROM reconciliation_checks c JOIN games g USING(game_id) WHERE g.season=? AND NOT c.independent')
    unavailable_pbp<-count('SELECT count(DISTINCT c.game_id) FROM pbp_reconciliation_checks c JOIN games g USING(game_id) WHERE g.season=? AND c.status=\'unavailable\' AND c.version=?',params=list(season,reconstruction_version))
    rows[[length(rows)+1L]]<-data.frame(season=season,source_games=source,raw_pbp_games=count('SELECT count(*) FROM schedule_inventory WHERE season=? AND has_pbp'),canonical_games=canonical,quarantined_games=source-canonical,reference_games=ref,reference_matched_games=nrow(match),reference_agree_games=sum(match$passed),reference_mismatch_games=sum(match$mismatch),reference_unavailable_games=sum(!match$mismatch & match$unavailable),reference_dependent_box_games=dependent,reconstruction_attempted=nrow(recon),possessions_reconciled=sum(recon$possessions_status=='reconciled'),lineups_reconciled=sum(recon$lineups_status=='reconciled'),pbp_metrics_unavailable_games=unavailable_pbp,resolved_team_periods=sum(recon$resolved_team_periods),expected_team_periods=sum(recon$expected_team_periods),fully_reconciled_games=sum(recon$game_id%in%match$game_id[match$passed] & recon$possessions_status=='reconciled' & recon$lineups_status=='reconciled'))
  }
  report<-do.call(rbind,rows)
  utils::write.csv(report,file.path(directory,'season_completeness.csv'),row.names=FALSE)
  ref_only<-DBI::dbGetQuery(con,'SELECT r.season,r.source_game_id,r.game_date,r.team_id home_team_id,r.opponent_team_id away_team_id FROM independent_team_totals r LEFT JOIN schedule_inventory i ON r.game_date=i.game_date AND r.team_id=i.home_team_id AND r.opponent_team_id=i.away_team_id AND r.season=i.season WHERE r.home AND i.game_id IS NULL ORDER BY r.season,r.game_date')
  utils::write.csv(ref_only,file.path(directory,'reference_only_games.csv'),row.names=FALSE)
  inventory_only<-DBI::dbGetQuery(con,'SELECT i.season,i.game_id,i.game_date,i.home_team_id,i.away_team_id FROM schedule_inventory i LEFT JOIN independent_team_totals r ON r.home AND r.season=i.season AND r.game_date=i.game_date AND r.team_id=i.home_team_id AND r.opponent_team_id=i.away_team_id WHERE r.source_game_id IS NULL ORDER BY i.season,i.game_date')
  utils::write.csv(inventory_only,file.path(directory,'source_only_games.csv'),row.names=FALSE)
  status<-DBI::dbGetQuery(con,'SELECT i.season,i.game_id,i.competition,i.validation_status,coalesce(s.possessions_status,\'not_reconstructed\') possessions_status,coalesce(s.lineups_status,\'not_reconstructed\') lineups_status FROM schedule_inventory i LEFT JOIN reconstruction_status s ON i.game_id=s.game_id ORDER BY i.season,i.game_id')
  utils::write.csv(status,file.path(directory,'game_validation_status.csv'),row.names=FALSE)
  # Full event-level diagnostics remain local; publish a compact category
  # summary without turning the Git repository into a data distribution mirror.
  exceptions<-DBI::dbReadTable(con,'quality_exceptions')
  if(nrow(exceptions)) {
    state<-DBI::dbReadTable(con,'reconstruction_status');loaded<-DBI::dbGetQuery(con,'SELECT game_id FROM games')$game_id
    conflict<-DBI::dbGetQuery(con,'SELECT DISTINCT game_id FROM reconciliation_checks WHERE passed IS DISTINCT FROM TRUE')$game_id
    exceptions$state<-'historical'
    exceptions$state[exceptions$stage%in%c('normalization','reference_recovery') | (exceptions$stage=='ingestion' & (!exceptions$game_id%in%loaded | exceptions$severity=='warning')) | (exceptions$stage=='independent_reconciliation' & exceptions$game_id%in%conflict)]<-'active'
    current<-exceptions$version==reconstruction_version
    exceptions$state[current & exceptions$stage=='possessions' & (exceptions$game_id%in%state$game_id[state$possessions_status!='reconciled'] | exceptions$severity=='warning')]<-'active'
    exceptions$state[current & exceptions$stage=='lineups' & exceptions$game_id%in%state$game_id[state$lineups_status!='reconciled']]<-'active'
    exceptions$category<-sub(' (espn:|[0-9]{5,}).*','',exceptions$rule)
    summary<-aggregate(rep(1L,nrow(exceptions)),exceptions[c('season','stage','state','severity','category')],sum)
    names(summary)[ncol(summary)]<-'findings'
  } else summary<-data.frame(season=character(),stage=character(),severity=character(),category=character(),findings=integer())
  utils::write.csv(summary,file.path(directory,'exception_summary.csv'),row.names=FALSE)
  header<-c('# Season completeness', '',paste('Generated in UTC:',format(Sys.time(),tz='UTC',usetz=TRUE)),paste('Reconstruction method:',reconstruction_version),'',
    'All counts refer to completed NBA franchise games, including play-ins and Cup finals.',
    'A completed backfill attempt is not a claim that every source game passes analytical validation.',
    'Reference counts come from a separate NBA-derived feed; neither archive is assumed complete.',
    'Reference-dependent team boxes are identified separately; comparisons to their own source are not independent.',
    'Raw archives are preserved locally. Missing, quarantined and unresolved games remain explicit.', '')
  compact<-report[c('season','source_games','canonical_games','quarantined_games','reference_matched_games','reference_agree_games','possessions_reconciled','lineups_reconciled','fully_reconciled_games')]
  writeLines(c(header,knitr::kable(compact,format='pipe',row.names=FALSE),'',
    'See season_completeness.csv for all denominators, game_validation_status.csv for each source game,',
    'reference_only_games.csv and source_only_games.csv for unmatched records, and exception_summary.csv.',
    'A reconciled reconstruction passed event totals, score conservation and control/clock constraints.',
    'Lineups additionally require exactly five unique players, complete period coverage and player-minute bounds.',
    'This does not certify unobserved ground truth or assign any defender. Both providers may share upstream errors.'),file.path(directory,'season_completeness.md'))
  invisible(report)
}
