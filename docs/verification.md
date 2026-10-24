# Verification record

Executed on 2026-10-23 using R 4.6.0 on Windows. No unexecuted check is
counted as passed. Startup locale notices and package patch-version notices
occur in this managed environment, outside test expectations.

- Real CC BY fixture: three games, no quality findings; no network required.
- Automated suite: **47 assertions passed, 0 failures, 0 test warnings, 0 skips**
  in a separate clone using the isolated restored library. Tests include keys,
  schema drift, joins, team assignments, dates,
  seasons, shooting totals, event completeness, failures, idempotence,
  incremental skips, transaction rollback, integer64 IDs and historical schemas.
- DuckDB initialization, related-table queries, local offensive-efficiency
  calculation and Arrow Parquet export executed successfully.
- `targets::tar_make()` completed; repeated execution reuses completed targets.
- Quarto CLI rendered `articles/luka-efficiency.qmd` to HTML successfully.
- Updated renv lockfile restored **76 packages into an empty isolated library**.
  Older lockfile versions initially needed unavailable Windows source-build
  tools; the final lockfile uses binaries verified available at review time.
- R/httr2 downloaded the 2015–16, 2025–26 and 2026–27 archive datasets.

## Local coverage

| Season | Games loaded | Date range | Status |
|---|---:|---|---|
| 2015–16 | 3 | 2016-06-13 – 2016-06-19 | Historical adapter sample; shot-value column unavailable |
| 2024–25 | 1,314 | 2024-10-22 – 2025-06-22 | All eligible published games except one quarantined game |
| 2025–26 | 3 | 2026-06-08 – 2026-06-13 | Adapter sample |
| 2026–27 | 3 | 2026-10-21 – 2026-10-22 | Current-season adapter sample |

Local warehouse after filtering: 1,323 games, 626 players, 30 teams,
35,259 player-box rows, 2,646 team-box rows, 625,665 PBP events,
234,930 shot attempts and 76,137 substitution descriptions.
Large warehouse/Parquet files are ignored; cloning provides the small fixture.

Game `401704652` has two inconsistent team scoring lines. In the publisher
file, New Orleans has 105 points versus 97 reconstructed from FG/3P/FT counts;
Portland has 103 versus 91. It remains excluded; source data are not repaired
by guessing. Failure details are retained in ingestion_runs and CSV reports.
Three All-Star showcase games (`401752955`–`401752957`) are excluded even
though the publisher marks them season_type=2. Franchise IDs are validated.

## Reproduction and CI

The original repository was inspected through connected GitHub metadata and
its public file listing; its files and history were left intact. New code was
committed and pushed to `just-the-stats-man/whats-your-bias-nba`.
Clean-clone offline tests, analytical example and targets builds passed.
The first targets run built the warehouse; the second skipped all completed
targets. CI uses the same pinned restore on Windows to avoid costly Linux
source compilation. Final hosted CI status is reported separately.
No paid feed, restricted scraping, defender model or salary optimizer was used.
