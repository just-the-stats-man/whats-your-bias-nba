# Phase 3 verification evidence

Production verification completed on 2026-10-25: **152/152 checks passed**.
This includes every original 85 integrity check, all 36 original snapshot-table
preservation checks, fresh hashes for all 9,645 original registered inputs,
9,739 current registered inputs, six NBA raw snapshots, 19 frozen NBA normalized
files and 2,002 saved physical reconstruction checkpoints.

The initial baseline had all 299 assertions passing before any engine change.
The expanded local suite passed 373 assertions; the subsequent physical
integrity assertion also passes in its targeted seven-assertion publication
test. Clean-clone and final CI evidence are recorded after the source milestone.

The shot milestone is commit `94e4a82`; its
[GitHub CI run](https://github.com/just-the-stats-man/whats-your-bias-nba/actions/runs/40241588880)
passed offline tests, the pinned-environment restore, targets fixture pipeline
and analytical demo.

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
