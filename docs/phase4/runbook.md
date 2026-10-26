# Phase 4 results and resumption

Phase 4 improves existing evidence and supplies separate analytical cohorts.
**No subscription, paid trial, authenticated provider request or billable call
was made.** Actual new-provider certified coverage is zero; the measured gains
below come from the existing licensed raw datasets.

| Measure | Verified Phase 3 | Phase 4 |
|---|---:|---:|
| Canonical games | 36,426 | 36,426 |
| Canonical shot rows | 3,531,387 | 3,641,807 |
| Certified shot attempts | 2,929,649 | 3,040,069 |
| Reconciled possessions | 2,181,653 | 2,181,653 |
| Certified five-player stints | 642,771 | 642,771 |
| Fully reconciled games | 9,669 | 9,669 |
| Assertions | 374 | 452 |
| Integrity/preservation checks | 152 | 259 |
| Fresh registered input hashes | 9,739 | 10,981 |

There are **110,420 additional canonical/certified attempts across 620 newly
shot-certified games**. These are not newly fully reconciled games. No new
possession/lineup reconstruction was justified by the recovered evidence: it
adds shot values and corroborated identity keys, not missing substitutions or
new control-transition observations. No broad historical reconstruction ran.

For 2023–24, certified attempts rise from 133,484 to **165,682**, or **70.93%**
of 233,601 canonical box FGAs; canonical shot rows rise from 133,661 to 165,859.
The [season comparison](shot_coverage_before_after.csv) covers all seasons and
separates canonical preservation from stricter certification. Older canonical
rows outside the certified view remain preserved, not newly certified.

## Results and limitations

- [Provider assessment](provider_assessment.md): ranked costs, granularity,
  shared-upstream risks, permission unknowns, targeted credit economics and
  conditional spending recommendation. Current actual spend: **$0**.
- [Terminal-score recovery](terminal_recovery_results.md): 100,211 attempts /
  562 games from unique observed final markers, with every original gate kept.
- [Verified roster-key recovery](roster_recovery_results.md): another 10,209
  attempts / 58 games; 5,560 separate NBA-native identity reconstructions.
- [Research datasets and R examples](research_datasets.md),
  [sizes/coverage](research_datasets.csv), [missingness](research_missingness.csv),
  and [selection diagnostics](selection_bias.md).
- [Current unresolved games](current/unresolved_games.csv) and
  [shooting discrepancies](current/shot_discrepancies.csv). The **26,708** games
  lacking both reconciled physical components remain unresolved. Partial staged
  value derivations are not balancing attempts or certified observations.
- [Activation instructions](paid_source_activation.md): no paid credentials
  required for CI, and no guessed private provider/export schemas.
- [Final checks](final_integrity.csv), [hash inventory](hash_verification.csv),
  [publication idempotence](idempotence.csv), and [verification](verification.md).

PBP Stats Tracking is the highest-value conditional paid pilot at the advertised
**$10/month**, because it could add tracking context unavailable locally.
Exact service seasons, row units, identifiers, local retention and derived
publication rights still need confirmation. Membership is not an API/bulk
license. Use DunkAPI's free-credit comparison before considering a $5 wallet
top-up or $19 plan; its shared lineage and real incremental value are untested.
No paid provider has demonstrated a certified coverage improvement here.

## Resume without rebuilding history

The sealed Phase 3 copy is `data/processed/phase4/baseline.duckdb`, with table
checksums and input metadata saved alongside it. It was created only after all
374 original assertions, all 152 checks and all 9,739 registered hashes passed.
**Never replace it with the current expanded database or rerun initialization
against the expanded warehouse.** Existing Phase 2/3 frozen exports remain intact.

Run writers sequentially from the repository root. Do not modify executing code.

```powershell
# Read-only diagnostics and the bounded terminal-marker scope.
Rscript scripts/phase4_terminal_scope.R
Rscript scripts/stage_terminal_shots.R
Rscript scripts/publish_terminal_shots.R

# One specific historical identity cluster, with all original gates retained.
Rscript scripts/stage_roster_shots.R
Rscript scripts/publish_roster_shots.R

# Preserve partial derivations separately; never promote failed games.
Rscript scripts/preserve_noncertified_enrichments.R

# Full fresh verification and separate research/selection reports.
Rscript scripts/verify_phase4.R
Rscript scripts/build_research_datasets.R
Rscript scripts/research_examples.R
Rscript scripts/test.R
```

Terminal staging is limited to 822 identified games across five seasons. Roster
staging is limited to 1,195 uncertified 2021–22 games. Raw/normalized inputs,
methods, exact source pointers and file hashes remain inspectable. Unchanged
terminal replay had 822 checkpoint hits; corrected roster replay had 1,195.
Reference and game caches belong to the sealed baseline and must not be moved
to a different warehouse by renaming their keys. Genuine input or method
changes require affected-scope diagnostics and newly validated results.

Publication only adds newly certified games. Superseded failed candidate/check
rows are archived; previously certified shots, boxes, events, possessions,
lineups, source manifests, hashes and exceptions survive. Original NBA failed
checks/rows are not overwritten by the new evidence paths. Repeating all
publications changed no counts or content checksums. A repeated noncertified
export recognized unchanged semantic evidence and added no registry records.

Do not run legacy full backfill/reconstruction/finalization scripts over this
warehouse or overwrite frozen earlier exports. The new research views remain
separate from ingestion and do not certify missing tracking or representativeness.
No individual defender assignments are inferred.

## Reproduction boundary

A clean checkout can run the offline tests, targets fixture pipeline, demo and
bounded research example with the pinned R environment. Reconstructing the
full production state additionally requires the licensed cached raw files and
saved baseline database/exports; multi-gigabyte raw/warehouse artifacts remain
local and excluded from Git. CI does not pretend to reproduce an unavailable
production feed. See the private `data/processed/phase4/` receipts/logs for exact
resumption state, including all checkpoint and raw response hashes.
