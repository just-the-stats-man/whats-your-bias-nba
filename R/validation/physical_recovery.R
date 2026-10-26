physical_recovery_integrity <- function(con) {
  sql<-c(
    component_artifact_missing="SELECT count(*) FROM reconstruction_component_methods m LEFT JOIN datasets d ON m.artifact_dataset_id=d.dataset_id WHERE d.dataset_id IS NULL",
    recovered_possession_method="SELECT count(*) FROM possessions p JOIN reconstruction_component_methods m ON p.game_id=m.game_id AND m.component='possessions' WHERE p.reconstruction_version IS DISTINCT FROM m.method OR (m.method LIKE 'pl-recovery-%' AND p.dataset_id IS DISTINCT FROM m.artifact_dataset_id)",
    recovered_lineup_artifact="SELECT count(*) FROM lineups l JOIN reconstruction_component_methods m ON l.game_id=m.game_id AND m.component='lineups' WHERE m.method LIKE 'pl-recovery-%' AND l.dataset_id IS DISTINCT FROM m.artifact_dataset_id",
    transformation_event_missing='SELECT count(*) FROM recovery_transformations a LEFT JOIN pbp_events e USING(game_id,event_id) WHERE a.event_id IS NOT NULL AND e.event_id IS NULL',
    transformation_player_invalid='SELECT count(*) FROM recovery_transformations a LEFT JOIN player_box_scores p ON a.game_id=p.game_id AND a.player_id=p.player_id WHERE p.player_id IS NULL OR p.did_not_play IS TRUE',
    transformation_artifact_missing='SELECT count(*) FROM recovery_transformations a LEFT JOIN datasets d ON a.artifact_dataset_id=d.dataset_id WHERE d.dataset_id IS NULL',
    projection_role_conflict="SELECT count(*) FROM (SELECT game_id,event_id,split_part(evidence,' ',1) field FROM recovery_transformations WHERE rule='exact_roster_name_in_observed_substitution' GROUP BY ALL HAVING count(DISTINCT player_id)>1)",
    projection_order_conflict="SELECT count(*) FROM (SELECT game_id,event_id FROM recovery_transformations WHERE rule='complete_numbered_same_clock_free_throw_trip' GROUP BY ALL HAVING count(DISTINCT derived_order)>1)",
    projection_duplicate_order='SELECT count(*) FROM (SELECT e.game_id,e.derived_event_order FROM reconstruction_event_projection e WHERE e.game_id IN (SELECT game_id FROM reconstruction_component_methods) GROUP BY ALL HAVING count(*)!=1)',
    reference_contradiction_recovered="SELECT count(*) FROM reconstruction_component_methods m JOIN reconciliation_checks c USING(game_id) WHERE m.method LIKE 'pl-recovery-%' AND c.passed IS FALSE")
  out<-data.frame(check=names(sql),violations=vapply(sql,function(q)as.numeric(DBI::dbGetQuery(con,q)[[1]][1]),numeric(1)));out$passed<-out$violations==0;out
}
