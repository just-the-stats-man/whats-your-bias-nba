# Historical execution verification — 2026-10-25

The historical run finished and passed final integrity checks. **NBA history is
not complete.** These are pinned-snapshot counts, not complete league populations.

| Strict canonical result | Preserved Phase 1 | Current | Historical portion |
|---|---:|---:|---:|
| Games | 14,067 | 36,426 | 22,359 |
| Reconciled possessions | 1,788,715 | 2,180,766 | 392,051 in 2,083 games |
| Five-player stints | 398,260 | 642,427 | 244,167 in 6,246 games |
| Both reconstructions and distinct-provider totals | 7,737 | 9,666 | 1,929 games |

The previous observation milestone already contained a 263-game historical
pilot. This execution adds 22,096 canonical games beyond that milestone. Its
corrected historical inputs supersede the pilot; the modern baseline is unchanged.

All **22 SDV partitions, 1993–94 through 2014–15**, were cached, normalized and
audited: **27,571 eligible schedule games**, **22,359 admitted complete boxes**,
and **5,212 quarantined games**. Whole NBA boxes recovered **4,660** failed ESPN
box families using unique exact identity/count evidence. Comparisons of those
boxes to NBA references are dependent. All available historical canonical box
seasons receive reference comparisons where a reviewed unique match exists.

The physical run evaluated **11,950 historical PBP games** in 14 isolated season
databases and published after worker integrity checks. Method
`pl-v1-74d5a845d796` is unchanged. Modern reconstruction was preserved. Frozen
inputs, checkpoints, results and receipts remain in
`data/processed/sdv-workers-0a2adb85c20cf1c3/`. A subsequent live resume reused
the published snapshot with an unchanged worker log: no physical games reran.

## Available families

| Family | Earliest evidence | Qualification |
|---|---|---|
| NBA game/team/player box observations | 1946–47 | Separate NBA namespace; early records and metrics are sparse |
| NBA events/shots/plausible coordinates | 1996–97 | Availability and limited consistency checks, not certified possessions |
| Strict canonical games and complete boxes | 1993–94 | Passed box gates; not a complete league denominator |
| Strict PBP/shots/reconciled possessions/lineups | 2001–02 | Only individually admitted/reconciled games |
| Provider-estimated tracking features | 2015–16 | 97,272 accepted context rows; 725 overtime rows failed context checks |
| Supplementary season totals/standings | 2022–23 | Five BoxScore Lab seasons; latest partial, NBA upstream identified |
| Optical trajectories / assigned defenders | Unavailable | No authorized local observation feed; no assignments invented |

The NBA observation layer retains **71,412 games**, **1,608,312 player box rows**,
**18,144,315 events** in **38,031 games**, and **6,333,996 candidate shots**. These
overlap canonical records and must not be added as unique games. Its 36,005
shot/score-consistent games do not establish full possession or lineup validity.

[Execution coverage](execution_season_completeness.md),
[CSV](execution_season_completeness.csv), and
[family extents](execution_availability_matrix.csv) cover all 81 available
seasons and separate data layers. [Reconciliation](execution_reconciliation.csv)
distinguishes independent, dependent, mismatched and unavailable comparisons.
“Independent” means distinct providers in this pipeline, not independently
observed ground truth. Historical `box_total_agree_games` includes self-comparisons
and is not an independent validation count.

## Executed verification

- **299 assertions passed**, with zero test failures, test warnings or skips,
  in the separate checkout using the independently restored pinned library.
  Tests cover legacy snapshot reuse, changed minutes/turnover inputs, exact
  mappings, input mutation and current-error reporting, alongside prior tests.
- **85 production checks passed:** 27 core, 42 historical and 16 execution checks.
  No canonical game lacks a current reconstruction status. Recording a failed
  or unavailable attempt is not a reconstruction pass.
- All original keys and row checksums in **19 baseline tables** match frozen
  Phase 1 exports, including microsecond diagnostic timestamps.
- SHA-256 verification passed for **9,645 registered entries / 9,641 paths**,
  six historical raw snapshots and 14 raw-gap JSON probes. Entries include raw
  and normalized inputs; they are not all distinct raw downloads.
- The separate checkout completed targets and the analytical demo. A repeated
  targets run skipped all four completed targets. No historical archive was
  rebuilt for this reproduction check.
- [CI passed the 299-assertion implementation](https://github.com/just-the-stats-man/whats-your-bias-nba/actions/runs/40233986580)
  at `d9e452b`; the final report commit also runs hosted checks. Locale and
  package-build notices occur outside test expectations and remain in local logs.

The expanded export contains **36 tables, about 585 MB**, in
`data/processed/execution_parquet/`. NBA exports remain in
`data/processed/historical_parquet/`; frozen baseline exports remain in
`data/processed/parquet/`. Raw data, DuckDB and full normalized snapshots stay
local and ignored by Git. GitHub contains implementation and compact reports.
Detailed verification evidence remains under `data/processed/phase2/`.

## Unresolved records and limits

Across **41,755 SDV source games**, **32,040** lack at least one passing physical
reconstruction: **25,606 historical** and **6,434 modern**. This includes useful
box-only games with unavailable PBP. **5,329** source games are quarantined,
including the unchanged **117 modern** games. Another 49 games pass both
reconstructions without full distinct-provider agreement.
[All current unresolved games](execution_unresolved_games.csv),
[historical games](historical_unresolved_games.csv), and
[modern games](unresolved_games.csv) identify each record and disposition.
Two tied-final NBA records remain in the separate
[NBA quarantine report](historical_quarantined_games.csv).

Common active findings include unexplained offensive-control changes, PBP/box
differences, ambiguous rebounds/held balls, score conservation, incomplete lineup
time coverage and player-minute bounds. No events, substitutions or defenders
were invented to force agreement. Superseded physical errors are excluded from
current summaries while retained in audit history. Successful games certify
the stated constraints, not unobserved ground truth.

Canonical shots remain sparse in some modern formats: 2023–24 has **1,430 stored
shot rows** versus **233,601 canonical box FGAs**. Missing shot rows never mean
zero attempts. The CSV reports box FGA, stored-row gaps and unavailable PBP
metrics; zero unclassified values among stored rows does not establish complete
capture. Broader NBA shot observations remain separately available. A fuller
validated event-to-shot adapter is needed before treating these canonical
seasons as complete shot samples.

[LeBron coverage](lebron_career_coverage.csv) spans available career seasons but
does not certify complete played-game or on-court coverage. Box rows include
DNP/unknown entries; playing counts require positive recorded minutes and lineup
counts require actual reconstructed membership. League denominators remain
unestablished. The 2026–27 snapshot is partial. Early franchise gaps, historical
definitions, conservative name/mapping exclusions and inconsistent events remain.

The [tracking/access assessment](tracking_assessment.md) records variables,
licenses, start evidence and prices. No subscription or paid API call was used.
DunkAPI was not tested: no credential was supplied and the user chose to proceed
without one. A $10 PBP Stats Tracking pilot is the first paid option to assess
if export/retention rights and coverage are confirmed; BBall Index is $5/month
for model benchmarks. No performance model or new article was produced.
