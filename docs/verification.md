# Verification record

The [2026-10-25 execution verification](execution_verification.md) records the
latest historical expansion, production checks and current limitations.

This page records the preserved Phase 1 milestone. Phase 2 adds separate
[historical availability reports](historical_completeness.md) and
[verification evidence](historical_verification.md). Its observation counts
must not be added to these overlapping provider records as unique games.

Executed on 2026-10-23/24 using R 4.6.0 on Windows. Only executed checks are
reported as passed. Managed-environment startup locale and package patch-version
notices occur outside test expectations.

## Automated checks

- The pre-resumption baseline passed all **158 assertions**. After fixing
  empty scoped raw partitions and legacy quarantine revalidation,
  **176 assertions passed, 0 failures, 0 test
  warnings, 0 skips**.
- Offline real fixtures cover three 2024–25 games, the 2016 Finals Game 7,
  and independently sourced NBA team/player records. Synthetic boundary cases
  supplement those observed records.
- Tests cover keys, schemas, joins, dates, seasons, scoring identities,
  idempotence, rollback, missing records, historical free-throw encodings,
  same-clock putback/rebound order, and-one scoring, retained free throws,
  overtime, ambiguous starters, invalid substitutions and player-minute bounds.
- Player/team aggregate checks reject conflicting attempts, missing playing
  player metrics and legacy snapshots that previously passed score checks.
  Withdrawal tests verify both derived-row cleanup and retained provenance.
- Reference tests deliberately change scores without changing matching keys,
  introduce unknown metrics, replace snapshots with withdrawn records, and
  verify that dependent box-score recovery cannot certify independent coverage.
- The pinned renv environment restored 76 packages into an empty isolated
  library. No new dependency was added for reconstruction.
- A separate clone passed all 176 assertions using that isolated library.
  Its targets pipeline and analytical demo succeeded, a repeated targets run
  reused completed targets, and Quarto rendered the article to HTML.
- Parallel reconstruction is tested against serial output on four observed
  games, including possession/event links, separate free-throw points, stints,
  five-player membership, minute checks and reconciliation benchmarks.
- Empty scoped player, team and PBP partitions retain zero facts and fail
  validation instead of terminating the entire recovery attempt.
- Revalidation tests admit a previously quarantined game only after the current
  gate passes, preserve its earlier failures, reject missing source records,
  and respect the selected seasons.
- Hosted Windows CI passed implementation commit
  [`cd8f824`](https://github.com/just-the-stats-man/whats-your-bias-nba/actions/runs/40114865637).

## Historical audit and provenance

The full historical rerun, targeted quarantine recovery and final verification
command exited successfully under method `pl-v1-74d5a845d796`. All **27 SQL integrity checks**
passed with zero violations. Every canonical game has a result under this
method; all **57 registered dataset files** and **14 raw-gap JSON files** passed
SHA-256 verification. The original 14,045-game cohort still agrees exactly with
the saved season-worker results, including its checkpoint timestamps: those
games were not reconstructed again. [22 revalidated games](revalidated_games.csv)
were processed separately after their cached records passed the current source
gate. Prior failures remain preserved; missing actors remain unknown.
Parquet exports were refreshed after reporting.
See [integrity results](warehouse_integrity.csv) and [table counts](warehouse_counts.csv).

Of **14,184** eligible source games, **14,067** are canonical and **117** remain
quarantined. Published facts include **1,788,715 possessions across 9,079 games**
and **398,260 five-player stints across 9,572 games**. **7,737 games** pass both
reconstructions and every required independent game-level comparison.
This is a completed processing and verification run with partial analytical
coverage, not a complete record of every historical possession or lineup.

**4,988 canonical games lack reconciled possessions; 4,495 lack reconciled
lineups; 6,317 lack at least one of the two.** [Unresolved games](unresolved_games.csv)
lists those games and the 117 quarantined games, with current error categories.
[Independent disagreements](reference_disagreements.csv) identifies all failed
metric comparisons across **38 canonical games**; their derived rows are withheld.
**34 games** use attributed alternative team boxes and cannot certify independent
box agreement against that same provider. **10 source-only** and **4 reference-only**
games remain explicit in the unmatched reports. Historical PBP attempt annotations
can remain unavailable even where independent box-level totals reconcile.

All available eligible games from 2015–16 through the pinned 2026–27 snapshot
were audited. Regular season, playoffs, play-ins and Cup finals are included;
preseason, All-Star showcases and unfinished games are excluded. This is an
audit of available publisher records, not a declaration that either archive
contains every game or every event.

See [season completeness](season_completeness.md) and its CSV for actual
canonical, quarantined, independent-reference and reconstruction denominators.
[Game statuses](game_validation_status.csv) identify each source game;
[exception categories](exception_summary.csv) distinguish active findings from
retained historical diagnostics. Detailed event-level findings remain in the
local warehouse's `quality_exceptions` table.

SDV Parquet files pin revision
`13f2e6ac8aed3cb6cfea6e81a0db088006357e95`. Independent Kaggle v524
`TeamStatistics.csv` and `PlayerStatistics.csv` are retained with metadata and
SHA-256 manifests. Player turnovers are summed from the independent player
records because NBA-reported team turnover totals change conventions across
eras. No benchmark is selected by whichever value matches ESPN.
The publishers' public metadata was rechecked on 2026-10-24: SDV's current
commit and Kaggle's current version still matched these pinned inputs;
Kaggle continued to declare CC0.

Some original ESPN team boxes fail scoring or player aggregate checks. Eligible
recoveries use entire attributed NBA-derived team records after validation;
no individual values are guessed. [Recovered box provenance](reference_dependent_boxes.csv)
identifies these games. Comparisons back to that same provider are explicitly
dependent and excluded from fully independent counts. Original files and
original failures remain preserved.

Missing independent player-team identifiers resolve only through unique
same-provider game, home/away, team and opponent metadata. No statistics are
filled. [Affected games](reference_metadata_resolutions.csv) retain resolution
counts. Missing ESPN total-turnover cells remain NULL; explicit independent
benchmarks validate observed PBP counts and retain their dataset/game lineage.
The canonical matched cohort records **34,169** metadata-resolved player rows
across **1,357 games**, without filling any missing statistic.

All 14 missing-PBP games were also checked in the licensed SDV raw JSON
archive, revision `e2c40720c72a98f427f8964deba8dd0e22ff1303`. Every play list
was empty. [Probe results](raw_gap_probes.csv) preserve URLs and hashes; these
games remain unavailable for reconstruction.

Published possessions require event/box totals, scoring conservation and
observable control/clock consistency. Published lineups additionally require
five unique players, complete period coverage and player-minute bounds.
Unknown historical missed-shot values remain unknown: PBP 3PA checks can be
unavailable while independently sourced box-level 3PA is still checked.
These gates establish consistency, not unobserved ground truth.

Raw files, DuckDB and full Parquet exports remain local and ignored by Git.
A fresh clone supplies small attributed fixtures and the processing code.
No defender assignment is inferred; `matchup_observations` remains empty.
No paid subscription or restricted NBA/ESPN scraping was used.

## Reproduction

```sh
Rscript scripts/setup.R
Rscript scripts/test.R
Rscript -e "source('scripts/load.R'); targets::tar_make()"
Rscript scripts/demo.R
quarto render articles/luka-efficiency.qmd

Rscript scripts/audited_backfill.R
Rscript scripts/reconstruct.R
# Alternative to the serial reconstruction above:
Rscript scripts/reconstruct_parallel.R
Rscript scripts/report_completeness.R
Rscript scripts/verify_historical.R
```

The first four analytical commands use offline fixtures after installation.
Historical commands retrieve only the selected publisher archives and resume
from immutable raw caches and reconstruction checkpoints. The licensed refresh
workflow runs game-level reconciliation and SQL integrity checks, then writes
reports and exports. Hosted cache/artifact storage is not a durable backup.
`verify_historical.R` requires the historical raw caches, checks that every
canonical game has a current-method result, verifies all registered file hashes
and the 14 raw-gap probes, and writes final integrity/count reports and exports.
It is a historical audit command, not part of the small offline sample workflow.

The original `nba-deckbuilding` repository and its history remain unchanged.
Implementation and verification reports are pushed to
`just-the-stats-man/whats-your-bias-nba`; hosted CI status is reported separately.
