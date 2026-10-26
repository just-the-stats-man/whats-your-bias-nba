# Warehouse architecture

Source adapter → immutable raw cache → schema checks → normalized frames →
quality gate → DuckDB transaction → Parquet snapshots → local queries.

R is the primary language. `config/schema.sql` is the executable schema.
DBI and DuckDB store data; Arrow writes Parquet; dplyr/dbplyr execute local
analytical queries. httr2 handles HTTP, targets builds the offline sample,
renv pins dependencies, testthat checks invariants, and Quarto demonstrates use.

Raw cache paths include the publisher revision. Dataset identities include
SHA-256, season and dataset kind. Each fact references its dataset, which
records source, URL, revision, retrieval time, raw path and raw row count.
Every load has a durable success/failure record. Validation happens before
facts are modified. Related writes are atomic; failed validation leaves the
previous warehouse intact. Repeating ingestion replaces the same keys.

Primary keys are enforced by DuckDB. Foreign-key equivalents are checked by
the quality gate to permit snapshot replacement without DuckDB foreign-key
update limitations. Nullable event participants are preserved as missing.
Stable player keys use namespaced ESPN IDs; `player_identifiers` can map
additional provider IDs onto the same key. Names are lookup conveniences,
never identity joins. Ambiguous names require an explicit key. Teams have
provider keys and season-specific identity records, avoiding a fixed present-
day abbreviation on historical games. An explicit franchise crosswalk maps the
independent NBA-derived totals onto ESPN team keys; player identifiers remain
provider-specific.

The archive partitions files by season, not game. An unchanged pinned
season is downloaded once. Game and player selection operate on that cache;
completed game IDs are skipped during incremental ingestion. Conditional
ETag requests support mutable updates. If a season file changes, its full
archive object must transfer; this source cannot offer per-game HTTP deltas.
Refresh explicitly replaces all selected completed game snapshots to capture
corrections. A new published revision can be selected via
`WYB_ARCHIVE_REVISION`; `main` is convenient but not immutable.

Backfill proceeds one season at a time and logs failed seasons, continuing
with the others. Reruns resume from committed game IDs. A season failing the
quality gate remains uncommitted; inspect the report and investigate upstream
rather than silently discard bad rows. One writer at a time is supported.
The GitHub refresh workflow serializes runs, caches data and uploads warehouse
artifacts; it never commits a database to Git. GitHub cache retention is not
durable hosting: run locally for persistent historical storage.

No API credentials are currently required. Future adapters must read keys
from environment variables and never log them. `.Renviron` is ignored.

## Audited reconstruction milestone

`scripts/audited_backfill.R` partitions by game, records source failures and
revalidates snapshots. It includes play-in type 5 and separates Cup finals.
Unlike the incremental loader, it does not skip an earlier validation decision
because a game ID exists. The raw schedule inventory includes quarantined
games. Superseded canonical games failing the current gate are withdrawn;
raw records, manifests and historical exceptions remain intact.

Reconstruction uses enriched event actors, scoring annotations, starters and
team-inclusive turnovers. Games commit in resumable batches. Only reconciled
game-level possessions and five-player stints are published. Statuses preserve
partial period resolution and minute discrepancies without ambiguous lineups.
See reconstruction.md for the rules and denominator definitions.

Independent NBA-derived totals use a versioned CC0-published Kaggle download
and exact date/franchise matching. Changed reference signatures invalidate
checkpoints; contradictions immediately withdraw derived rows. Alternative
whole-team-box recovery retains its provider and flags dependent comparisons.
Mutable SDV branches resolve to commits before caching; Kaggle versions have
separate paths. Scheduled refresh rejects an unrecognized independent license.

Parquet export streams from DuckDB rather than loading the entire warehouse
into R. Git contains compact aggregate/per-game status reports; raw files,
databases and full event diagnostics remain local or in expiring artifacts.
Run writers sequentially: DuckDB permits one writer process. Offline tests
and fixtures never require source HTTP requests.
## Phase 3 incremental publication

The Phase 2 `execution_parquet/` and separate NBA `historical_parquet/` exports
are frozen inputs. Phase 3 shot staging writes season/input/method checkpoints
and immutable Parquet evidence, then publishes additions in a separate DuckDB
transaction. Unchanged season signatures avoid extraction; unchanged published
signatures also avoid replacing millions of candidate rows. Publication still
checks conflicts against preserved facts and DNP records.

Physical recovery screens explicit source patterns, saves a content-hashed
result per game and relevant input signature, and compares every affected
previously certified component. It publishes only newly passing components,
with component-level method/lineage metadata and exact prior failed-row history.
Partial resumes merge into the full checkpoint index in deterministic order.
Raw events are never reordered in storage; audited derived columns are exposed
separately. The original method fingerprint remains stable.

Do not run legacy finalization exports over the frozen Phase 2 directories.
The Phase 3 runbook describes local evidence, publication, preserved snapshots,
standalone reports and clean-clone fixture reproduction. No current processing
requires a paid service or a new basketball data download.
