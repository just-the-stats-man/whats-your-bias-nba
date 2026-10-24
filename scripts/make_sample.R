# Maintainer-only fixture extraction from the unmodified CC-BY-4.0 archive.
source('scripts/load.R')
dir.create('data/sample',recursive=TRUE,showWarnings=FALSE)
specs <- c(schedules='nba_schedule',player_box='player_box',team_box='team_box',pbp='play_by_play')
raw <- lapply(specs,function(prefix)as.data.frame(arrow::read_parquet(paste0('data/raw/',prefix,'_2025.parquet'))))
luka <- raw$player_box[raw$player_box$athlete_id==3945274 & raw$player_box$season_type==2, ]
ids <- head(unique(as.character(luka$game_id)),3)
stopifnot(length(ids)==3)
bundle <- lapply(names(specs),function(kind){
  d <- raw[[kind]]; d <- d[as.character(d$game_id) %in% ids, ]
  path <- paste0('data/sample/',kind,'.rds'); saveRDS(d,path,version=3)
  list(data=d,path=path,url=sprintf('https://raw.githubusercontent.com/sportsdataverse/hoopR-nba-data/%s/nba/%s/parquet/%s_2025.parquet',archive_revision,kind,specs[[kind]]),revision=archive_revision)
})
names(bundle)<-names(specs)
saveRDS(bundle,'data/sample/bundle.rds',version=3)
print(quality_report(normalize_bundle(bundle,'2024-25')))
