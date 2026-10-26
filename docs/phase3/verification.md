# Phase 3 verification evidence

Production verification completed on 2026-10-25: **152/152 checks passed**.
This includes every original 85 integrity check, all 36 original snapshot-table
preservation checks, fresh hashes for all 9,645 original registered inputs,
9,739 current registered inputs, six NBA raw snapshots, 19 frozen NBA normalized
files and 2,002 saved physical reconstruction checkpoints.

The initial baseline had all 299 assertions passing before any engine change.
The expanded suite passed **374 assertions**, including all original 299, in
the clean checkout of `84cd77f`. All 79 exact package versions in `renv.lock`
were verified in the restored environment, including R's recommended packages.
The clean checkout's targets fixture pipeline and analytical demo also passed.

The shot milestone is commit `94e4a82`; its
[GitHub CI run](https://github.com/just-the-stats-man/whats-your-bias-nba/actions/runs/40241588880)
passed offline tests, the pinned-environment restore, targets fixture pipeline
and analytical demo.

The physical recovery milestone is commit `84cd77f`; its
[GitHub CI run](https://github.com/just-the-stats-man/whats-your-bias-nba/actions/runs/40268870552)
also passed environment restore, offline tests, targets and the demo. The final
documentation revision does not alter the verified processing logic or data.

Both publications were repeated against production and changed no row counts
or content checksums. The two-game physical resume reused both checkpoints and
preserved the complete checkpoint-index hash. The 26-season unchanged shot
resume performed no extraction. All 707 affected certified possession and 367
certified lineup components passed their regression gates. The original engine
fingerprint remains `pl-v1-74d5a845d796`.

See [final integrity](final_integrity.csv), [input hash counts](hash_verification.csv),
[idempotence](idempotence.csv), [component methods](component_methods.csv), and
the [results/runbook](runbook.md). Full raw data and production files remain
local; CI exercises licensed bundled fixtures, not an unavailable full raw feed.
