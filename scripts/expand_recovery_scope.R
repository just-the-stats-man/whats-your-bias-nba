source('scripts/load.R');con<-phase3_snapshot_connection()
tryCatch({
  ids<-DBI::dbGetQuery(con,"SELECT DISTINCT e.game_id FROM pbp_events e LEFT JOIN players n USING(player_id) WHERE (lower(event_type) LIKE '%substitution%' AND (player_id IS NULL OR secondary_player_id IS NULL OR player_id='espn:0' OR secondary_player_id='espn:0' OR ends_with(lower(trim(description)),lower(trim(n.name))) OR ends_with(lower(trim(description)),lower(trim(n.name))||'.')) AND description LIKE '% enters the game for %') OR (regexp_matches(lower(event_type),'jumpball|jump ball') AND (tertiary_player_id IS NULL OR tertiary_player_id='espn:0') AND description LIKE '% gains possession%')")$game_id
  old<-utils::read.csv('data/processed/phase3/recovery_scope.csv',colClasses=c(game_id='character'))
  scope<-DBI::dbGetQuery(con,'SELECT g.game_id,g.season,r.possessions_status,r.lineups_status FROM games g JOIN reconstruction_status r USING(game_id) ORDER BY g.season,g.game_id')
  scope<-scope[scope$game_id%in%unique(c(ids,old$game_id,'401909841')),]
  ft_ids<-old$game_id[old$free_throw_pattern%in%TRUE]
  scope$free_throw_pattern<-scope$game_id%in%ft_ids;scope$explicit_missing_actor<-scope$game_id%in%ids
  utils::write.csv(scope,'data/processed/phase3/recovery_scope.csv',row.names=FALSE);print(table(scope$season));cat(nrow(scope),'games in dependency-limited scope\n')
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
