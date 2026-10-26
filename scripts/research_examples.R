# Run against a prepared warehouse. Keep this separate from collection/modeling.
source('scripts/load.R');con<-connect_warehouse()
tryCatch({
  install_research_views(con)
  print(research_tbl(con,'player_boxes') |> dplyr::filter(.data$player_id=='espn:1966',.data$participation_status=='observed_participation') |> dplyr::group_by(.data$season) |> dplyr::summarise(observed_games=dplyr::n(),fga=sum(.data$fga,na.rm=FALSE)) |> dplyr::collect())
  print(research_tbl(con,'shots') |> dplyr::filter(.data$season=='2023-24',.data$coordinate_status=='observed') |> dplyr::select(dplyr::all_of(c('game_id','event_id','player_id','points_attempted','made','x','y'))) |> head(5) |> dplyr::collect())
  print(research_tbl(con,'possessions') |> dplyr::filter(.data$season=='2023-24') |> dplyr::select(dplyr::all_of(c('possession_id','game_id','offense_team_id','points','reconstruction_version'))) |> head(5) |> dplyr::collect())
  print(research_tbl(con,'lineup_matchups') |> dplyr::filter(.data$season=='2023-24') |> head(5) |> dplyr::collect())
},finally=DBI::dbDisconnect(con,shutdown=TRUE))
