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
day abbreviation on historical games. Cross-provider mappings are not yet loaded.

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
