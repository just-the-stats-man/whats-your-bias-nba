# Verification evidence

The Phase 3 baseline was reverified before changes: **374 assertions, all 152
checks and 9,739 registered input hashes passed**. Its 65 base tables and full
database copy were sealed. Every frozen-table checksum was rechecked before
the roster cache migration.

Final local verification passes **452 assertions and 259 checks**. The original
152 checks remain included by name and execution. All **10,981** registered
input fingerprints pass fresh hashing, including all **9,739 Phase 3** and
**9,645 Phase 2** originals. Nineteen frozen NBA normalized files, six NBA raw
snapshots, 2,002 Phase 3 physical checkpoints and 2,017 Phase 4 method/game
checkpoints pass their checks. Another 1,052 noncertified derivation artifacts
were separately hashed. The detailed receipts remain local; aggregate evidence
is in [final_integrity.csv](final_integrity.csv) and [hash_verification.csv](hash_verification.csv).

All original certified shot rows are preserved exactly. Original failed rows
are either still active or preserved in explicit history tables. Every original
canonical possession, stint, member, minute/status record, source and dataset
record survives. The four-file Phase 2 physical engine fingerprint remains
`pl-v1-74d5a845d796`. No validation precision bound was relaxed.

Every publication was repeated with zero additions and identical content
checksums; see [idempotence.csv](idempotence.csv). The terminal resume reused
822/822 artifacts. The fixed roster resume reused 1,195/1,195 and preserved the
full index hash. The noncertified export replay added no registry records.

An intermediate CI run caught a static dependency cycle in method-version
helpers. Commit `396a44e` removed that cycle without changing recorded method
hashes or rerunning certified results; its
[CI run](https://github.com/just-the-stats-man/whats-your-bias-nba/actions/runs/40278953611)
passed. The research milestone `5a99343` also
[passed CI](https://github.com/just-the-stats-man/whats-your-bias-nba/actions/runs/40279595864).
The final source revision is checked again through the
[offline workflow](https://github.com/just-the-stats-man/whats-your-bias-nba/actions/workflows/ci.yml)
before task completion. Superseded failed/cancelled runs are not presented as
successful runs.

Tests include terminal-marker conflicts/order, missing identity keys,
cross-provider/stat/minute contradictions, private-key handling, explicit
approval/credit caps, cache corruption, failed requests, duplicate records,
FT versus FG, missing coordinates, model-estimate separation, export grain and
permissions, research cohort separation, exactly-five/time linkage and stable
checkpoint inputs. No live paid integration is claimed. Clean-clone fixture
reproduction and the production hash/integrity audit are distinct checks.
