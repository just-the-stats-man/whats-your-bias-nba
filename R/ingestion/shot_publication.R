# Append certified observations. Phase 2 rows and source metadata are immutable.
publish_shot_recovery <- function(con,path='data/processed/phase3/shot_stage.duckdb') {
  shot_recovery_schema(con)
  DBI::dbExecute(con,paste0('ATTACH ',DBI::dbQuoteString(con,normalizePath(path,winslash='/')),' AS shot_stage (READ_ONLY)'))
  on.exit(DBI::dbExecute(con,'DETACH shot_stage'),add=TRUE)
  DBI::dbWithTransaction(con,{
    for(t in c('sources','datasets','dataset_dependencies'))DBI::dbExecute(con,paste0('INSERT OR IGNORE INTO ',t,' BY NAME SELECT * FROM shot_stage.',t))
    DBI::dbExecute(con,'CREATE OR REPLACE TEMP TABLE _changed_shot_seasons AS SELECT s.season FROM shot_stage.shot_recovery_checkpoints s LEFT JOIN shot_recovery_checkpoints c USING(season) WHERE s.signature IS DISTINCT FROM c.signature OR s.method IS DISTINCT FROM c.method')
    for(t in c('shot_recovery_candidates','shot_recovery_checks','shot_recovery_checkpoints')) {
      DBI::dbExecute(con,paste0('DELETE FROM ',t,' WHERE season IN (SELECT season FROM _changed_shot_seasons)'))
      DBI::dbExecute(con,paste0('INSERT INTO ',t,' BY NAME SELECT * FROM shot_stage.',t,' WHERE season IN (SELECT season FROM _changed_shot_seasons)'))
    }
    DBI::dbExecute(con,"CREATE TABLE IF NOT EXISTS shot_publication_conflicts AS SELECT c.*,CAST(NULL AS VARCHAR) publication_reason FROM shot_recovery_candidates c WHERE FALSE")
    DBI::dbExecute(con,'DELETE FROM shot_publication_conflicts')
    DBI::dbExecute(con,"INSERT INTO shot_publication_conflicts SELECT c.*,'preserved_canonical_fields_disagree' FROM shot_stage.shot_recovery_candidates c JOIN shot_attempts s USING(game_id,event_id) WHERE c.certification_status='certified' AND (c.player_id IS DISTINCT FROM s.player_id OR c.team_id IS DISTINCT FROM s.team_id OR c.points_attempted IS DISTINCT FROM s.points_attempted OR c.made IS DISTINCT FROM s.made)")
    DBI::dbExecute(con,"INSERT INTO shot_publication_conflicts SELECT c.*,'observed_shooter_contradicts_box_DNP' FROM shot_stage.shot_recovery_candidates c JOIN player_box_scores p ON c.game_id=p.game_id AND c.player_id=p.player_id AND c.team_id=p.team_id WHERE c.certification_status='certified' AND p.did_not_play IS TRUE")
    DBI::dbExecute(con,"UPDATE shot_recovery_candidates SET certification_status='noncertified',reason='game_publication_evidence_conflict' WHERE game_id IN (SELECT game_id FROM shot_publication_conflicts)")
    DBI::dbExecute(con,'CREATE TABLE IF NOT EXISTS shot_recovery_withdrawn_rows AS SELECT * FROM shot_attempts WHERE FALSE')
    DBI::dbExecute(con,"INSERT INTO shot_recovery_withdrawn_rows SELECT s.* FROM shot_attempts s WHERE s.dataset_id LIKE 'shot-recovery:%:candidates' AND s.game_id IN (SELECT game_id FROM shot_publication_conflicts) AND NOT EXISTS(SELECT 1 FROM shot_recovery_withdrawn_rows w WHERE w.game_id=s.game_id AND w.event_id=s.event_id)")
    DBI::dbExecute(con,"DELETE FROM shot_attempts WHERE dataset_id LIKE 'shot-recovery:%:candidates' AND game_id IN (SELECT game_id FROM shot_publication_conflicts)")
    added<-DBI::dbExecute(con,"INSERT INTO shot_attempts SELECT c.game_id,c.event_id,c.player_id,c.team_id,c.points_attempted,c.made,c.x,c.y,c.coordinate_system,CASE WHEN c.value_status='reconstructed' THEN 'reconstructed_unique_constraints' ELSE 'provider_observed' END,c.dataset_id||':candidates' FROM shot_recovery_candidates c WHERE c.certification_status='certified' AND NOT EXISTS(SELECT 1 FROM shot_attempts s WHERE s.game_id=c.game_id AND s.event_id=c.event_id)")
    DBI::dbExecute(con,"CREATE OR REPLACE VIEW certified_shot_attempts AS SELECT c.* FROM shot_recovery_candidates c JOIN shot_attempts s USING(game_id,event_id) WHERE c.certification_status='certified' AND c.player_id=s.player_id AND c.team_id=s.team_id AND c.points_attempted=s.points_attempted AND c.made=s.made")
  })
  invisible(added)
}
