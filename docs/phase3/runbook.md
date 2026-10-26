# Phase 3 recovery results and runbook

The warehouse remains incomplete. Phase 3 recovers existing recorded evidence;
it does not certify complete historical seasons or infer missing tracking.

## Verified results

| Measure | Phase 2 (`c391b10`) | Phase 3 | Change |
|---|---:|---:|---:|
| Canonical games | 36,426 | 36,426 | 0 |
| Canonical shot rows, including preserved older rows | 2,327,773 | 3,531,387 | +1,203,614 |
| Shot attempts certified under the new gates | Not previously established | 2,929,649 | Separate validated cohort |
| Possession rows | 2,180,766 | 2,181,653 | +887 |
| Five-player stints | 642,427 | 642,771 | +344 |
| Reconciled possession games | 11,162 | 11,167 | +5 |
| Reconciled lineup games | 15,818 | 15,827 | +9 |
| Fully reconciled games | 9,666 | 9,669 | +3 |
| Original production integrity checks | 85 passed | 85 passed | All retained |
| Expanded integrity/preservation checks | — | 152 passed | Includes original 85 |
| Registered input hashes freshly verified | 9,645 | 9,739 | Original inputs preserved |

Fully reconciled requires both physical components plus all 20 passing
distinct-provider game-total comparisons. NBA-recovered boxes compared with
NBA totals remain dependent and cannot enter that column. Distinct providers
can still share upstream errors.

The extractor previously required a 2/3-point attempt annotation. That field
is absent/sparse in several source schemas, despite recorded FG flags and
outcomes. Explicit descriptions, made-basket values, uniquely linked existing
NBA events and uniquely solvable box constraints recover values. Free throws
are excluded explicitly. Missing coordinates no longer discard attempts;
standard locations require the [identified publisher frame](../phase3_coordinate_evidence.md).
No attempt, outcome, value or location is invented to balance a total.

For 2023–24, canonical shots increase from 1,430 to 133,661; 133,484 pass the
new gates against 233,601 box FGAs (57.14%). Observed canonical-game FG
candidates number 233,588. A small aggregate count gap does not imply that
every game reconciles: unknown values, identity/context disagreements and
offsetting team/game discrepancies remain disqualifying. The strict view is
`certified_shot_attempts`; the preserved canonical table has a larger count.

The physical recovery projection corrects complete numbered FT order and
explicit substitution-name role encoding. Five possession games and eight
lineup games pass after supported transformations; another lineup game passes
fresh current-input gates without an event transformation. No flag/minute
tolerance was loosened. All 707 affected previously certified possession
components and all 367 affected certified lineup components still pass.
No newly certified game was added by the tested missing-starter or explicit
jump-winner rules. The [transformation audit](transformation_audit.csv),
[component methods](component_methods.csv) and [2,002-game recovery attempts](recovery_attempts.csv)
retain the actual scope and evidence.

## Coverage and unresolved observations

- [Shot completeness before and after by season](shot_completeness.csv): canonical
  box FGA, observed/validated attempts, valid/missing/invalid locations, unmatched
  source observations, noncertified candidates and recoverable share.
- [FGA/FGM/3PA/3PM discrepancies](shot_discrepancies.csv) and
  [candidate exception categories](shot_exceptions.csv): unknowns remain distinct
  from mismatches. Three games with 14 shooter/DNP contradictions (457 candidate
  attempts) are withheld as whole games.
- [Separate NBA observation links](nba_shot_link_coverage.csv): source-native
  observations without a certified canonical match remain in the historical
  observation tables. These overlap ESPN evidence and cannot be summed as
  independent new attempts. Unmatched is not evidence that no shot happened.
- [Physical coverage by season](reconstruction_completeness.csv),
  [cross-source metric comparisons](cross_source_reconciliation.csv),
  [unresolved games](unresolved_games.csv), and
  [unresolved categories by season](unresolved_categories.csv).

There are 26,708 canonical games without both reconciled physical components:
10,409 have no admitted PBP, 7,380 have missing/inconsistent critical event
totals, 8,875 retain physical-sequence or lineup ambiguity, and 44 have current
reference-total disagreements. These are mutually exclusive diagnostic groups,
assigned in the report's stated precedence; they are not proofs that every
game is irrecoverable. Earlier detailed exceptions remain preserved and may
include superseded reference findings. Use current status and current checks
for current eligibility, rather than counting every historical exception.

The [cached failure totals](cached_failure_totals.csv) and
[season distribution](cached_failure_seasons.csv) record the pre-fix diagnostic
screening used to prioritize work. Categories overlap and include superseded
findings; the [recovery strategy](../phase3_recovery_strategy.md) distinguishes
parsing/order defects from source inconsistencies, missing records and ambiguity.

Remaining sequences include anonymous team rebounds, held balls without an
explicit winner, incomplete/mislabelled event streams, incomplete substitution
names, contradictory identities/DNP flags, ambiguous period fives and source
minute disagreements. Further algorithmic recovery is not ruled out; this
phase has not certified a global solver for all ambiguous cross-period minute
constraints. Gaps and conflicts require additional event/identity evidence
before they can be resolved safely. Missing optical measurements and defender
assignments require an authorized observation feed. No new basketball data
source, paid API or DunkAPI credential was used.

## Resume safely

Run from the repository root with the pinned `renv.lock` environment. DuckDB
writers must run sequentially; do not edit an executing script or method.
The verified initial baseline is saved in
`data/processed/phase3/phase2_baseline.rds`. **Do not regenerate that baseline
against the already expanded warehouse.** Its 36 frozen Phase 2 export tables,
9,645 registered inputs, six NBA raw snapshots and 19 NBA normalized exports
are preserved. No full historical ingestion is necessary.

```powershell
# Diagnose from frozen verified input exports.
Rscript scripts/phase3_diagnose.R

# All cached PBP seasons; optional numeric end year selects one season.
Rscript scripts/stage_shot_recovery.R
Rscript scripts/publish_shot_recovery.R

# Recompute the explicit affected scope only when diagnostics/inputs change.
Rscript scripts/diagnose_recovery_scope.R
Rscript scripts/expand_recovery_scope.R
Rscript scripts/stage_physical_recovery.R
Rscript scripts/publish_physical_recovery.R

# Fresh integrity, preservation, hash, idempotence and coverage reports.
Rscript scripts/verify_phase3.R
Rscript scripts/test.R
```

Shot staging signs raw hashes, complete relevant canonical events, boxes,
rosters, games, NBA snapshots/transforms and extraction method. Unchanged
seasons skip extraction, and unchanged published signatures skip replacing the
candidate tables. Publication-only changes do not force extraction. Immutable
evidence files live in `data/processed/phase3/shots/<season>/<signature>/`.

Physical staging signs each affected game's full events, roster, team boxes,
reference checks/totals, source manifests and method. Results live in
`data/processed/phase3/physical/`. A partial resume, for example
`Rscript scripts/stage_physical_recovery.R 220215013 400974774`, checks those
inputs and merges cached results into the complete index. The executed two-game
resume had two checkpoint hits and an identical complete-index SHA-256.
The unchanged 26-season shot resume performed no extraction. Repeating both
publications changed no rows or content checksums; see [idempotence](idempotence.csv).
Relevant input changes invalidate their dependent output; never reuse a stale
artifact by renaming its signature.

Publication preserves old certified components, original raw/canonical PBP,
source-native identifiers, registry rows and provenance. Exact prior failed
status/minute rows are archived when a component is recertified. Legacy
`reconstruct*.R`/`finalize_execution.R` commands reproduce earlier phases;
do not run them over this Phase 3 warehouse or its frozen export directories.
Use the Phase 3 reports across all component versions.

## Verification and reproducibility

The 299 original assertions remain included. Added tests cover absent modern
annotations, historical FT values/order, explicit two/three versus FT classes,
ambiguous values/joins, contradictory outcomes, coordinate sentinels/frames,
exact actor roles, missing/contradictory starter evidence, original minute
bounds, conflict/DNP publication gates, preserved records and repeat publication.
Two full licensed historical/modern source excerpts are bundled with manifests
and attribution for offline regression reproduction.

[Final integrity](final_integrity.csv) includes all 85 original checks, 14 shot
checks, ten physical-method checks, 36 preserved-table checks and seven hash/
regression checks. [Hash inventory](hash_verification.csv) records 9,739
registered inputs, all 9,645 originals, 36 Phase 2 snapshots, 19 separate NBA
normalized files, six NBA raw snapshots and 2,002 game checkpoints.
Raw file hashes and complete local evidence remain under `data/processed/phase3/`.

A clean clone can run the offline tests, targets fixture pipeline and demo
with the pinned dependencies. Rebuilding the full production warehouse also
requires the already licensed pinned raw files and saved Phase 2 exports;
multi-gigabyte raw/warehouse files are intentionally excluded from Git. CI
verifies fixture reproducibility rather than pretending to reproduce private
local production inputs. See [verification status](verification.md) for commits,
test counts and CI evidence.
