source('scripts/load.R');con<-connect_warehouse()
tryCatch({
  DBI::dbExecute(con,'SET threads=4');DBI::dbExecute(con,"SET memory_limit='3GB'")
  print(publish_terminal_shots(con))
  checks<-rbind(warehouse_integrity_report(con),historical_integrity(con),execution_integrity(con),shot_recovery_integrity(con),physical_recovery_integrity(con),phase3_preservation(con),phase4_preservation(con),terminal_shot_integrity(con))
  utils::write.csv(checks,'docs/phase4/recovery_integrity.csv',row.names=FALSE);stopifnot(all(checks$passed))
  cat(nrow(checks),'integrity/preservation checks passed\n')
  phase3_reports(con,'docs/phase4/current')
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
