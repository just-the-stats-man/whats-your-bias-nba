# Research cohorts and R extraction

These are documented observation cohorts, not representative samples or new
basketball outcome models. Install with `Rscript scripts/build_research_datasets.R`.
Use `research_tbl(con, family)` for lazy R/dbplyr queries; collect only the
needed columns/seasons. [Current sizes and temporal coverage](research_datasets.csv)
and [field missingness](research_missingness.csv) are generated from the warehouse.

## Box statistics

`player_boxes` and `team_boxes` contain admitted canonical player-game and
team-game observations, regardless of whether PBP, possessions or lineups are
available. Keys are `(game_id, player_id)` and `(game_id, team_id)`. Game/team/
player keys and `dataset_id` join their canonical dimensions and source registry.
DNP rows remain explicit. Positive recorded minutes or live counting statistics
establish participation; a recorded zero-minute row is not automatically a DNP
or a missing observation. Source precision is retained.

`nba_player_boxes` and `nba_team_boxes` are a **separate NBA-native namespace**
extending to 1946–47. Keys are `(snapshot_id, source_row)`; game/player/team IDs
join the historical dimensions. Row validation is required, but every metric's
availability/status must also be inspected. A pre-era three-point field is not
an observed zero. Do not stack these rows with overlapping canonical boxes or
silently treat `nba:*` and `espn:*` as interchangeable. Use the documented game
bridge and verified one-to-one player links when comparison is necessary.

These families support career/longitudinal questions without selecting only
physically reconstructed games. Exact complete-career or league denominators
are still unestablished; observed records are not proof of complete coverage.

## Certified shots

`shots` contains only `certified_shot_attempts`, keyed by `(game_id,event_id)`.
It exposes native/raw row pointers, derived-value rules/status, reference IDs,
coordinate status and registered evidence dataset ID. It excludes free throws,
unmatched identities, unresolved outcomes/values, duplicate events, source
conflicts and games failing any shooting gate. `shot_exclusions` retains the
noncertified canonical-game candidates and reasons. Additional staged versions
must not be counted as additional independent attempts.

Location analysis additionally requires `coordinate_status='observed'`.
Missing/invalid locations remain null and do not discard a valid attempt.
No tracking observations were acquired: nearest-defender distance and assigned
defender columns are null, and tracking status is `not_collected`. A location
or opponent lineup does not establish a responsible defender. Authorized future
tracking exports require validated row units and identifiers before joining.

## Reconciled possessions

`possessions` contains reconciled individual possessions, keyed by
`possession_id`, with game/period/offense/defense, event/time boundaries, points,
provenance and actual reconstruction method. It is not restricted to games
whose lineups also pass. Technical/retained-FT points remain separately stored
in `non_possession_points`; summing possession points alone is not always the
final score.

`possession_lineups` links a possession/team to a certified stint only when it
covers the **entire positive time interval and event-order interval**. Key:
`(possession_id,team_id)`. Ambiguous candidates, zero-duration possessions and
possessions crossing a substitution are not assigned a convenient five. Missing
links do not exclude the possession from its broader cohort. Individual player
linkage comes from recorded event participants and five-player memberships,
not an invented individual allocation of possession credit.

## Certified lineup stints

`lineups` contains certified five-player stints, keyed by `lineup_id`, with
exact player lists, team/game/period, complete positive intervals and source
artifacts. `lineup_matchups` gives positive intersections of home/away certified
stints, keyed by `(home_lineup_id,away_lineup_id)`. It is one undirected exposure
interval per pair, not an individual defender assignment.

`lineup_possession_counts` adds **fully contained** offense/defense possession
counts. These are explicitly not all possessions overlapping the stint and
must not be used as an unqualified efficiency denominator. Points or possession
counts are never prorated across a substitution by overlap time.

## Reproducible R queries

```r
source('scripts/load.R')
con <- connect_warehouse()
install_research_views(con)

# Broad observed career cohort, including games without valid possessions.
career <- research_tbl(con, 'player_boxes') |>
  dplyr::filter(player_id == 'espn:1966',
                participation_status == 'observed_participation') |>
  dplyr::select(game_id, season, team_id, minutes, points, fga, dataset_id) |>
  dplyr::collect()

# A distinct NBA-native historical cohort; metric-specific filtering required.
history <- research_tbl(con, 'nba_player_boxes') |>
  dplyr::filter(season == '1959-60', points_status == 'observed') |>
  dplyr::select(game_id, player_id, points, points_status, snapshot_id, source_row) |>
  dplyr::collect()

shots <- research_tbl(con, 'shots') |>
  dplyr::filter(season == '2023-24', coordinate_status == 'observed') |>
  dplyr::select(game_id, event_id, player_id, points_attempted, made, x, y,
                value_status, source_dataset_id, reference_snapshot_id) |>
  dplyr::collect()

possessions <- research_tbl(con, 'possessions') |>
  dplyr::filter(season == '2023-24') |>
  dplyr::collect()
lineups <- research_tbl(con, 'lineups') |>
  dplyr::filter(season == '2023-24') |>
  dplyr::collect()

DBI::dbDisconnect(con, shutdown = TRUE)
```

`scripts/research_examples.R` runs bounded extracts against the prepared local
warehouse. A clean-clone fixture without a shot-certification layer returns an
empty research shot cohort; it never substitutes all legacy canonical shots.
The legacy `get_player_shots()` API exposes the broader preserved canonical
table and is not the stricter research cohort.
