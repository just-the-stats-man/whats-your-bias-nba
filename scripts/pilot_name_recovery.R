source('scripts/load.R');con<-phase3_snapshot_connection()
tryCatch({
  names<-DBI::dbGetQuery(con,'SELECT player_id,name FROM players');xs<-readRDS('data/processed/phase3/lineup_pilot_inputs.rds')
  out<-lapply(xs,function(x){x$p$name<-names$name[match(x$p$player_id,names$player_id)];a<-recovery_projection(x$e,x$p);po<-reconstruct_possessions(a$e,x$g,a$p);lu<-reconstruct_lineups(a$e,x$g,a$p);data.frame(game_id=x$g$game_id,season=x$g$season,changes=nrow(a$audit),before=length(x$lu$issues),after=length(lu$issues),new_lineup_pass=!length(lu$issues),rules=paste(unique(a$audit$rule),collapse='; '))})
  z<-do.call(rbind,out);utils::write.csv(z,'data/processed/phase3/name_pilot.csv',row.names=FALSE);print(z[z$new_lineup_pass|z$changes>0,])
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
