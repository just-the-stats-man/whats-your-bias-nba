# Data dictionary

Phase 4 adds `phase4_terminal_score_evidence` (canonical/NBA game, observed
terminal event and physical source row), `phase4_shot_publications` (game/method/
signature/artifact), `phase4_verified_player_boxes` (validated NBA-native records
with reconstructed team keys), and `phase4_roster_team_evidence` (recorded home
flag, existing player/roster crosswalk, all ten counts and original minute bounds).
Original failed NBA records remain untouched. `phase4_prior_shot_recovery_*`
tables preserve every superseded failed candidate/check row.

`phase4_noncertified_shot_enrichments` holds versioned partial value derivations
and hashed staging pointers, not additional independent attempts or certified
rows. `supplementary_snapshots`, `supplementary_permission_receipts`,
`supplementary_export_records`, and the optional `dunkapi_play_observations`
are source-specific staging schemas for future approved access. No live paid
data was imported. Observation unit, permissions, model estimates and source
missingness remain separate from canonical promotion.

See [research dataset grains/keys](phase4/research_datasets.md),
[generated coverage](phase4/research_datasets.csv), and
[activation boundaries](phase4/paid_source_activation.md).

Phase 3 adds an evidence layer without rewriting Phase 2 facts:

| Relation | Grain / meaning |
|---|---|
| `shot_recovery_candidates` | Normalized source dataset + physical raw row; includes unmatched and noncertified FG candidates, native event IDs, raw/transformed locations, per-field statuses, exact NBA reference pointers and rejection reasons |
| `shot_recovery_checks` | Dataset/game/team/metric; observed versus expected FGA/FGM/3PA/3PM |
| `shot_recovery_checkpoints` | Season; complete relevant input signature and method |
| `certified_shot_attempts` | Current game/event evidence that passes all shooting and actor gates and agrees with a canonical row; use this view for the Phase 3 validated shooting cohort |
| `shot_publication_conflicts` | Current conflicting observations; includes shooter/DNP contradictions and preserved canonical field disagreements |
| `shot_recovery_withdrawn_rows` | Preserved evidence for any new recovery row withdrawn by a publication gate; no Phase 2 row is removed |
| `reconstruction_component_methods` | Game + possession/lineup component; actual method, complete input signature, registered result artifact |
| `recovery_transformations` | Event/player-level explicit name-role or numbered-FT derivation, original and derived order, evidence and artifact |
| `reconstruction_event_projection` | Original PBP columns plus `derived_*` participant/order columns for published recovery evidence; canonical PBP stays unchanged |
| `phase3_prior_reconstruction_status`, `phase3_prior_lineup_minute_checks` | Exact original rows before a failed component was recertified |

`shot_attempts` includes preserved older rows as well as new certified additions;
its total is not the size of the stricter validated view. In the evidence view,
`value_status` distinguishes observed and reconstructed values. A uniquely
box-constrained value is not an independent verification of that box. Location
status is separate from attempt certification: missing/invalid locations remain
null, with published native pairs retained. Aggregate observed attempts and
validated attempts are separate denominators. NBA source observations have a
separate link-coverage report and must not be added to overlapping ESPN counts.

Some games combine a preserved Phase 2 component and a recovered component.
Use `reconstruction_component_methods` for those games; a single status-row
version cannot describe both components. Reports in `docs/phase3/` use all
current methods and supersede earlier coverage counts without rewriting the
historical Phase 2 reports.

Historical execution adds `sdv_history_status` (game/family admission status),
`sdv_history_checkpoints` (season/input signature), and `sdv_nba_player_links`
(reviewable exact identity evidence for whole NBA box recovery). Earlier failed
quality exceptions remain historical evidence; use current status tables to
measure present admission. See [SDV execution](sdv_execution.md).

`tracking_provider_context` uses `(dataset_id, source_row)` as its immutable
provider-record key. It contains NBA game/team IDs and unmapped shooter/nearest
name labels. `tracking_provider_estimates` adds `metric` to that key and keeps
both `reported_value` and nullable standardized `value`. Status is `estimated`,
`source_missing` or `failed_validation`; uncertainty is unavailable. Neither
table supplies an assigned/responsible defender or a canonical shot event ID.

`boxscorelab_player_season_totals`, `boxscorelab_team_standings`, and
`boxscorelab_team_game_results` retain provider-native CSV fields plus dataset,
record ordinal, native key and validation status. Numeric CSV fields are
retained as provider text to preserve meanings; only documented counting
columns enter `boxscorelab_reconciliation`. Player team labels can combine all
season stints. Estimated rates/ratings are not observed counting statistics.
Provider agreement with other NBA-derived totals is explicitly dependent.

`execution_unresolved_games.csv` reports current family admission and physical
states. Active physical errors must match the current event dataset and failed
stage; superseded failures remain in the warehouse audit history. The separate
LeBron coverage report distinguishes box rows (including DNP/unknown entries),
recorded positive-minute appearances, and actual reconstructed lineup membership.
Unclassified shot values and unavailable PBP metrics are counted explicitly.

PBP reconciliation records retain the original source `box_value` separately
from a comparison's `benchmark_value`, type, dataset and provider game ID.
An independently reported total can validate a missing source field without
filling that field. Independent team totals also record `reference_player_rows`
and `mapped_player_team_rows` for strict provider-metadata identity resolution.

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
