# Historical expansion verification — 2026-10-24

Verified implementation: `3f5d038b0b994a19c1b0ba0d9517ad4dba49dd57`.
This is a completed historical **observation** milestone, not a declaration that
NBA history or historical possession reconstruction is complete.

| Historical layer | Verified count |
|---|---:|
| Seasons with admitted NBA game records | 81, from 1946–47 through the partial 2026–27 snapshot |
| Admitted NBA game records | 71,412 |
| Player box rows | 1,608,312 |
| Games passing the 28 comparable player/team count checks | 48,482 |
| Games with recorded NBA PBP | 38,031, beginning in 1996–97 |
| Recorded event rows | 18,144,315 |
| Candidate field-goal rows | 6,333,996 |
| Shot rows passing the coordinate plausibility screen | 5,629,673 |
| Games passing all ten within-upstream shot/score checks | 36,005 |
| Provider person identities | 6,820 |
| Normalization checkpoints at the current transformation | 193; none outdated |
| Added tracking observations / defender assignments | 0 / 0 |

Recorded shot rows and plausible positions are availability counts. They are
not all validated attempts or optical tracking measurements. The ten-check
subset establishes only score and shooting-count consistency with NBA-derived
boxes, not full possession/lineup completeness or independent measurement.
Official season totals and standings remain unavailable; the season-total
views are explicitly partial covered-game sums. These provider counts overlap
the canonical ESPN cohort and must not be added as unique games.

## Executed checks

- **237 assertions passed**, zero failures, test-expectation warnings or skips.
  All original 176 assertions remain, with historical schema, century,
  missingness, immutable-path, turnover-component, raw-pointer, quarantine,
  rollback, scope-preservation and idempotence regressions added.
- **27 original warehouse integrity checks passed** and **42 historical
  integrity checks passed**.
- Checksums and row counts for all original keys in **19 tables** match the
  frozen Phase 1 Parquet exports, including diagnostic microsecond timestamps.
  The original reconstruction fingerprint remains `pl-v1-74d5a845d796`.
- SHA-256 verification passed for **65 existing dataset-manifest entries**
  (62 distinct paths), **six historical raw snapshots**, and **14 archived
  raw-gap JSON probes**. Some manifests share input files; these are not
  counts of distinct raw files. Raw inputs remain unchanged and ignored by Git.
- A separate clean Git checkout was fast-forwarded to the implementation
  commit. Using the independently restored, pinned 76-package library with
  project-library precedence, **237 assertions passed with zero test warnings**;
  the targets pipeline and existing analytical demo completed successfully.
  This reused the dependency cache and bundled fixtures rather than downloading
  or rebuilding the full historical archive again.
- [GitHub CI for the verified implementation passed](https://github.com/just-the-stats-man/whats-your-bias-nba/actions/runs/40148114928).
  Startup locale and R package build-version notices occur outside test
  expectations and are distinguished from test failures/warnings.
- The live historical pilot resume skipped already completed physical work.
  Historical reference refresh now verifies unchanged protected benchmarks and
  preserves unrelated diagnostic rows in SQL; benchmark changes roll back.
- Nineteen historical tables/views were exported separately to ignored
  `data/processed/historical_parquet/` (about 590 MB). Original exports remain
  the preservation baseline.

The preserved baseline still has 14,067 canonical games, 1,788,715 possessions
across 9,079 games, 398,260 five-player stints across 9,572 games, and 7,737 games
meeting the previous full cross-provider reconciliation definition. That
definition distinguishes providers; it does not prove independent physical
measurement. None of these original records was replaced by this expansion.

## Explicit unresolved records and limits

The 2003–04 ESPN pilot has 1,271 eligible games: 263 passed strict box ingestion
and 1,008 remain quarantined. All 263 admitted games failed possession/lineup
gates. There are **zero additional validated possessions or stints** from the
pilot. Current canonical game count is therefore 14,330, with the added 263
explicitly unresolved for physical reconstruction. See
[every unresolved pilot game](historical_unresolved_games.csv).

Two NBA game metadata records have impossible tied finals:
`nba:0020400090` (2004–05) and `nba:0021000028` (2010–11). Their source records,
hashes and affected raw row pointers are retained; they are excluded from the
admitted historical analytical families. See
[quarantine details](historical_quarantined_games.csv). No score was invented.

Of the 14 modern ESPN games with no raw PBP, ten have separately attributed NBA
events. Seven pass the limited NBA shot/score checks; three fail them, and four
have no matched NBA event records. These observations improve available
evidence but do not recover canonical possessions or lineups. See the
[modern gap audit](historical_modern_gap_audit.csv).

Early seasons are sparse. Full-season expected denominators remain unestablished
by an independently complete schedule. Broad pre-2015 ESPN physical reruns are
deferred because the pilot exposed missing event classifications and other
inconsistencies; repeating that expensive run without an adapter change would
not resolve them. The next resumable step is a tested historical event adapter,
followed by selected unverified seasons, with the original method/cohort kept
intact. New immutable Games snapshots also require a reviewed migration rather
than automatic replacement of valid existing observations.

No paid provider was accessed or subscribed to. Historical tracking, explicit
defensive assignments, reviewed player crosswalks, and official complete season
totals/standings remain unfinished. See the [provider and pricing audit](historical_sources.md),
[capability/missingness framework](missingness_and_research.md),
[season matrix](historical_completeness.md), and [resumption instructions](historical_expansion.md).
