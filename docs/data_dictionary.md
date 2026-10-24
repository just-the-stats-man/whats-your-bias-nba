# Data dictionary

Column names and SQL types are in `config/schema.sql` and the idempotent
existing-warehouse migrations in `R/database/warehouse.R`.
All identifiers are VARCHAR, counts INTEGER, money DOUBLE in nominal USD,
dates DATE and ingestion/report times TIMESTAMP (UTC from R system time).
Rates are computed from counts rather than stored rounded percentages.

| Table | Grain / primary key | Meaning and joins |
|---|---|---|
| sources | source_id | Publisher, license and attribution |
| datasets | dataset_id | Raw file fingerprint, revision, time, URL; fact provenance |
| ingestion_runs | run_id | Attempt status, season, timestamps, error or counts |
| seasons | season | YYYY-YY; end_year is provider season year |
| teams | team_id | Stable provider team identity |
| team_identities | team_id, season | Historical name and abbreviation; joins teams/seasons |
| players | player_id | Stable identity, display and accent-insensitive search name |
| player_identifiers | provider, provider_id | Many providers map to players.player_id |
| games | game_id | Season, type (2 regular / 3 postseason), date, both teams, final scores |
| player_box_scores | game_id, player_id | Team at that game, minutes, shot/FT counts, points, AST, TOV, rebounds, DNP |
| team_box_scores | game_id, team_id | Official team totals, including team turnovers distinct from individual turnovers |
| pbp_events | game_id, event_id | Provider order, period/clock, description, participants, cumulative scores |
| shot_attempts | game_id, event_id | PBP-derived 2/3-point attempts, made flag, provider coordinates |
| substitutions | game_id, event_id | Provider substitution description; no unverified in/out assignment |
| lineups | lineup_id | Reconciled team/period stint, elapsed start/end/duration and attribution |
| lineup_players | lineup_id, player_id | Exactly five unique players per published stint |
| matchup_observations | observation_id | Assignment type and epistemic category required; reserved |
| contracts | contract_id | Player agreement, signing date, guarantees; reserved |
| salaries | contract_id, season, team_id | Salary, cap hit, option; reserved |
| injuries | report_id | Timestamped reported status/reason; reserved |
| possessions | possession_id | Game/period offense, event/time boundaries, points and ending reason |
| possession_events | game_id, event_id | Possession mapping or neutral/administrative/retained-FT attribution |
| non_possession_points | game_id, event_id | Separately conserved technical/retained-FT points |
| reconstruction_status | game_id | Method, input/reference signatures, statuses and period denominators |
| lineup_minute_checks | game_id, player_id | Reconstructed/box seconds, precision bound and pass flag |
| independent_team_totals | source_id, source_game_id, team_id | Attributed NBA-derived reference totals |
| reconciliation_checks | game_id, team_id, reference_dataset_id, metric | Values, difference, nullable pass and independence flag |
| schedule_inventory | game_id | All raw eligible games, table-presence flags, competition and quarantine status |
| quality_exceptions | exception_id | Persistent game/season/stage/rule diagnostics, dataset, severity and method |
| pbp_reconciliation_checks | game_id, team_id, metric | PBP/box values, nullable pass, match/mismatch/unavailable status and unknown-event count |
| dataset_dependencies | dataset_id, parent_dataset_id | Raw-parent lineage for normalized independent team/player records |

Every analytical fact has a dataset_id. Player/team IDs referenced by facts
join their dimensions; games join seasons. Shots/substitutions join event
keys. Defender, contract, salary and injury tables have no ingestion adapters or fabricated
rows. Their future writers must enforce the same referential validation.

Missing means unknown/unobserved, never zero. DNP rows retain provider null
statistics; analyses should filter DNP explicitly. Player minutes are provider
decimal minutes, not seconds. Invalid coordinate sentinels outside ±100 are
converted to NA, raw values remain in raw files. Coordinate orientation and
units remain uncalibrated; do not interpret these as NBA Stats shot-chart units.
Event IDs are preserved as exact strings, including 64-bit provider integers.
PBP ordering is provider sequence, not a repaired causal ordering. Missing
events, duplicate order and broken joins are quality errors. Final PBP score
disagreements are warnings requiring review before possession analysis.

Games distinguish regular season, playoffs, play-in and NBA Cup final.
ESPN season_type=5 is play-in; Cup finals otherwise share season_type=2.
PBP retains secondary/tertiary participants, type IDs and scoring annotations.
Player boxes store starters; team boxes store both player and team-inclusive
turnovers. Explicit-evidence DNP corrections and excluded anonymous non-playing
placeholders are logged with raw row indexes. See reconstruction.md for gates.
