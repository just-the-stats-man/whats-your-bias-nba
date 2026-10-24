source('scripts/load.R')
con <- connect_warehouse()
tryCatch({
  games <- get_player_games('Luka Doncic','2024-25',con)
  print(offensive_efficiency(games))
  print(head(get_game_pbp(games$game_id[1],con),3))
  print(head(get_player_shots('Luka Doncic','2024-25',con),3))
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
