# Data dictionary

The exact column names and SQL types are in `config/schema.sql`.
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
| lineups | lineup_id | Reserved validated stint boundaries; unavailable in initial ingestion |
| lineup_players | lineup_id, player_id | Five-player membership bridge; reserved |
| matchup_observations | observation_id | Assignment type and epistemic category required; reserved |
| contracts | contract_id | Player agreement, signing date, guarantees; reserved |
| salaries | contract_id, season, team_id | Salary, cap hit, option; reserved |
| injuries | report_id | Timestamped reported status/reason; reserved |

Every analytical fact has a dataset_id. Player/team IDs referenced by facts
join their dimensions; games join seasons. Shots/substitutions join event
keys. Reserved tables have schemas but no ingestion adapters or fabricated
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
