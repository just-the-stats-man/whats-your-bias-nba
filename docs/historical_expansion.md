# Historical expansion: operation and limits

This phase adds NBA-derived observations alongside the verified ESPN warehouse. It does **not** declare NBA history complete. The season matrix and exception reports, rather than the presence of a downloaded file, determine supported analyses.

## Reproduce and resume

Use the pinned R environment (`Rscript scripts/setup.R`). From the repository root:

```sh
Rscript scripts/cache_historical_license.R
Rscript scripts/expand_historical.R boxes
Rscript scripts/expand_historical.R events
Rscript scripts/report_historical_expansion.R
```

The first command captures and checks the publisher's CC0 declaration. A changed/missing license stops downloads. API responses and requested versions remain distinguishable; a metadata response may describe the current dataset even when files are requested at v524. No account or payment is required. Raw CSV/Parquet files are cached without replacement. A registered path whose bytes change is rejected.

The box and event commands commit by season and skip matching snapshot/transformation checkpoints. Optional end years select a subset, for example `Rscript scripts/expand_historical.R events 2004`. All available historical NBA seasons are selected by default. CSV inputs are parsed once per box run; Parquet is scanned lazily. Existing possession/lineup code and its fingerprint are unchanged. Never run two writers against the same DuckDB file.

The final reporting command expects the frozen Phase 1 exports in `data/processed/parquet/` for preservation checks. Keep these exports until verification finishes. New historical exports belong in `data/processed/historical_parquet/`; do not overwrite the baseline as a shortcut to making preservation checks pass. A fresh clone can reproduce the historical adapters through the bundled synthetic fixtures (`Rscript scripts/test.R`); reproducing the original full baseline additionally requires the documented Phase 1 backfill and reconstruction.

The additional ESPN pilot is resumable with:

```sh
Rscript scripts/expand_sdv_history.R 2004
```

It imports historical NBA reference totals, audits the pinned SDV season, preserves existing player names, and runs the existing strict reconstruction gates. The default is the 2003–04 pilot. Explicit end years 2002–2015 select other archived seasons. **Do not launch a broad physical rerun until historical event classification is addressed:** all 263 admitted pilot games failed possession/lineup validation. The archive lacks modern attempt classifications, and individual games also have scoring, timing or substitution discrepancies. The other 1,008 eligible ESPN pilot games failed box ingestion. Raw NBA observations for those dates remain separately available; failed ESPN evidence is not silently patched to match them.

## Tables and definitions

`historical_games` uses `nba:` game and team namespaces. Season centuries require the recorded date and NBA season suffix to agree. Positive final scores and unique game identities are required. Earlier records include substantial gaps and omit defunct teams; they are not a complete schedule or a source of official historical standings.

`historical_team_boxes` and `historical_player_boxes` retain raw row pointers and per-metric status columns. Standardized unavailable values are null. Immutable source files retain original zero placeholders. Historical category start dates are lower bounds, followed by per-row checks; availability is not inferred from a year alone. A scoring-identity pass (`validation_status='observed'`) is narrower than a complete validated box.

The season report's box-check count requires the 28 era-applicable comparable player/team checks across both teams. Minutes are not reconciled by this aggregate check. The raw team's reported turnover field has inconsistent component conventions; its comparison remains diagnostic and is excluded from this count. Historical reference turnover benchmarks use known player sums, with a separately recorded team-only component for total turnovers. Unknown components remain null. Self-comparisons are never independent validation.

`historical_events` preserves provider action numbers, descriptions, ISO/source clocks and actor IDs. Its raw row pointer is the Parquet physical row number, independent of parallel scan order. `historical_shots` distinguishes legacy and live raw coordinate systems. It preserves raw coordinates and marks unavailable/sentinel positions; `(0,0)` legacy positions are conservatively unavailable. Raw live positions use a 0–100 plausibility screen; legacy bounds are screening rules, not a validated geometric transform. Neither coordinate system is transformed into the other. Coordinates are shot locations, not player trajectories. Distances come from the source; impossible zero-distance three-pointers remain unavailable. No model supplies missing locations, results or attempted values.

`historical_event_checks` compares field-goal counts, explicit three-point classifications and last recorded positive cumulative scores against NBA-derived boxes. It does not test free throws, turnovers, substitutions or possession boundaries. Even all ten checks passing establishes only shot/score consistency within a shared upstream. The reports separately retain failed and unavailable checks.

`historical_team_season_totals` and `historical_player_season_totals` are **partial covered-game sums**, separated by competition. `*_recorded_rows` counts available box rows, not official games played; player rows can include DNP/unknown appearances. No official full-season totals, standings, missing appearances, league averages or era-adjusted estimates are manufactured. Rates require an explicitly justified appearance/coverage denominator.

`historical_players` preserves NBA person identifiers and recorded names. It does not fuzzy-match ESPN athletes. `historical_team_history` preserves provider labels without accepting them as reviewed franchise reassignment evidence. Game links require a unique season/date/franchise-ID pair. The present Charlotte/New Orleans crosswalk is deliberately unavailable for ambiguous earlier periods; labels do not override that restriction.

## Reports and remaining work

- [Availability by season](historical_completeness.md), [full counts](historical_completeness.csv), and [family/status matrix](historical_availability_matrix.csv).
- [Metric missingness](historical_metric_availability.csv), [exceptions](historical_exception_summary.csv), [within-upstream event checks](historical_event_consistency.csv), and [cross-provider comparisons](historical_reconciliation.csv).
- [Modern gap investigation](historical_modern_gap_audit.csv), [snapshot hashes](historical_snapshots.csv), [new integrity checks](historical_integrity.csv), and [original-table preservation](baseline_preservation.csv).

Detailed row-level exceptions, game links, box comparisons and event checks remain in ignored `data/processed/reports/*.parquet`. They retain source pointers and disagreements rather than replacing observations. Existing Phase 1 unresolved-game reports remain intact. The pilot's detailed unresolved games are exported separately by the historical report.

Next work should implement and test a provider-specific historical event adapter, then rerun only eligible unverified seasons. The failed pilot is a checkpoint and a diagnostic, not proof that historical possessions are impossible. Broad historical SDV reconstruction, complete official season totals/standings, reviewed player crosswalks and licensed tracking remain unfinished. No subscription was purchased; see [source/access assessment](historical_sources.md) and [missingness/research limits](missingness_and_research.md).
