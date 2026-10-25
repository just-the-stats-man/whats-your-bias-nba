source('scripts/load.R')
folder<-'data/processed/phase3';dir.create(folder,recursive=TRUE,showWarnings=FALSE)
con<-DBI::dbConnect(duckdb::duckdb(),dbdir=':memory:')
tryCatch({
  DBI::dbExecute(con,'SET threads=4');DBI::dbExecute(con,"SET memory_limit='2GB'")
  for(path in list.files('data/processed/execution_parquet',pattern='[.]parquet$',full.names=TRUE)) {
    table<-sub('[.]parquet$','',basename(path))
    DBI::dbExecute(con,paste0('CREATE VIEW ',table,' AS SELECT * FROM read_parquet(',DBI::dbQuoteString(con,normalizePath(path,winslash='/')),')'))
  }
  queries<-list(
    shot_flags="SELECT g.season,count(*) events,count(*) FILTER(WHERE e.shooting_play IS TRUE AND NOT regexp_matches(lower(e.event_type),'free throw')) fg_events,count(*) FILTER(WHERE e.shooting_play IS TRUE AND regexp_matches(lower(e.event_type),'free throw')) ft_events,count(*) FILTER(WHERE e.shooting_play IS TRUE AND NOT regexp_matches(lower(e.event_type),'free throw') AND e.points_attempted IN (2,3)) annotated_fg,count(*) FILTER(WHERE e.shooting_play IS TRUE AND NOT regexp_matches(lower(e.event_type),'free throw') AND e.scoring_play AND e.score_value=0) made_fg_zero_value,count(*) FILTER(WHERE e.shooting_play IS TRUE AND NOT regexp_matches(lower(e.event_type),'free throw') AND e.scoring_play IS NULL) unknown_fg_result FROM pbp_events e JOIN games g USING(game_id) GROUP BY g.season ORDER BY g.season",
    failure_seasons="SELECT g.season,e.stage,regexp_replace(e.rule,' (espn:|[0-9]{5,}).*','') category,count(*) findings,count(DISTINCT e.game_id) games FROM quality_exceptions e JOIN games g USING(game_id) JOIN reconstruction_status r ON r.game_id=e.game_id AND r.dataset_id=e.dataset_id WHERE e.severity='error' AND ((e.stage='possessions' AND r.possessions_status!='reconciled') OR (e.stage='lineups' AND r.lineups_status!='reconciled')) GROUP BY g.season,e.stage,category ORDER BY g.season,e.stage,games DESC",
    failure_totals="SELECT e.stage,regexp_replace(e.rule,' (espn:|[0-9]{5,}).*','') category,count(*) findings,count(DISTINCT e.game_id) games FROM quality_exceptions e JOIN reconstruction_status r ON r.game_id=e.game_id AND r.dataset_id=e.dataset_id WHERE e.severity='error' AND ((e.stage='possessions' AND r.possessions_status!='reconciled') OR (e.stage='lineups' AND r.lineups_status!='reconciled')) GROUP BY e.stage,category ORDER BY games DESC",
    actor_teams="SELECT g.season,e.event_type,count(*) events,count(DISTINCT e.game_id) games FROM pbp_events e JOIN games g USING(game_id) JOIN player_box_scores p ON e.game_id=p.game_id AND e.player_id=p.player_id WHERE e.team_id IS DISTINCT FROM p.team_id AND (e.shooting_play OR regexp_matches(lower(e.event_type),'rebound|turnover')) GROUP BY g.season,e.event_type ORDER BY games DESC",
    jump_examples="SELECT g.season,e.* FROM pbp_events e JOIN games g USING(game_id) JOIN reconstruction_status r USING(game_id) WHERE r.possessions_status!='reconciled' AND regexp_matches(lower(e.event_type),'jump') ORDER BY g.season,e.game_id,e.event_order LIMIT 80",
    control_examples="SELECT g.season,e.* FROM quality_exceptions e JOIN games g USING(game_id) JOIN reconstruction_status r ON r.game_id=e.game_id AND r.dataset_id=e.dataset_id WHERE e.stage='possessions' AND e.rule LIKE 'unexplained change%' AND r.possessions_status!='reconciled' ORDER BY g.season,e.game_id LIMIT 60",
    input_files="SELECT DISTINCT d.* FROM datasets d JOIN dataset_dependencies x ON d.dataset_id=x.parent_dataset_id WHERE d.dataset_id LIKE 'sdv:pbp:%' UNION SELECT DISTINCT d.* FROM datasets d JOIN pbp_events e USING(dataset_id) WHERE d.dataset_id LIKE 'sdv:pbp:%'")
  for(name in names(queries)) {
    result<-DBI::dbGetQuery(con,queries[[name]])
    utils::write.csv(result,file.path(folder,paste0(name,'.csv')),row.names=FALSE,na='')
    cat(name,':',nrow(result),'rows\n')
  }
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
