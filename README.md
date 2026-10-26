# What's Your Bias? — NBA research warehouse

Reproducible data infrastructure for checking basketball claims with evidence.
The first milestone is a local warehouse, not a player ranking or predictive
model. Original R code is MIT licensed; sample NBA data has separate CC BY 4.0
and CC0 attribution in `data/sample/ATTRIBUTION.md`.

Historical expansion now has an additive NBA observation pipeline with explicit
metric missingness, season checkpoints and provider-specific shot coordinates.
See the [historical runbook and limits](docs/historical_expansion.md),
[SDV execution runbook](docs/sdv_execution.md),
[execution season matrix](docs/execution_season_completeness.md), and
[tracking/access assessment](docs/tracking_assessment.md). Historical observations and
failed reconstruction attempts are reported separately from validated possessions
and lineups; downloaded history is not a completeness claim.
The [executed verification and remaining limits](docs/execution_verification.md)
record final counts, integrity checks, preserved baseline rows and unresolved games.
The previous [nba-deckbuilding](https://github.com/just-the-stats-man/nba-deckbuilding)
repository and its history are preserved unchanged.

## Quick start

Requirements: R 4.6.x, Git, internet for dependency installation. Quarto CLI is
optional for rendering the article. No API account or paid credentials needed.
From a terminal in the cloned repository:

```sh
git clone https://github.com/just-the-stats-man/whats-your-bias-nba.git
cd whats-your-bias-nba
Rscript scripts/setup.R
Rscript scripts/test.R
Rscript scripts/sample.R
Rscript scripts/demo.R
```

After installation, tests, sample ingestion and the demo work offline. Setup
restores `renv.lock` into ignored `.library/`; `scripts/load.R` adds that library
without changing your global R installation. `scripts/lock.R` updates the lock
only when dependencies intentionally change. CI installs dependencies before
running the fixture tests; it does not test installation without a network.

## Pipeline and refresh

The targets/sample/demo commands use the bundled fixture warehouse. Run those
in a separate checkout when preserving an expanded production warehouse.
For historical execution use [the SDV runbook](docs/sdv_execution.md), followed
by `scripts/report_historical_expansion.R` and `scripts/finalize_execution.R`.
The original `verify_historical.R` below is the Phase 1 workflow and refreshes
its Parquet export directory; retain the frozen baseline for the additive
historical preservation check instead of overwriting it.

```sh
Rscript -e "source('scripts/load.R'); targets::tar_make()"
Rscript scripts/ingest.R 2024-25
Rscript scripts/audited_backfill.R
Rscript scripts/reconstruct.R
Rscript scripts/reconstruct_parallel.R
Rscript scripts/report_completeness.R
Rscript scripts/verify_historical.R
quarto render articles/luka-efficiency.qmd
```

The audited backfill defaults to season end years 2016–2027; optional numeric
arguments select individual end years (2016 means 2015–16). It processes every
eligible game, logs exceptions and quarantines unresolved records. Its default
revision is pinned in `R/sources/sportsdataverse.R`. To update a current
season from the publisher's mutable branch, set `WYB_SEASON=2026-27` in your
environment and run `Rscript scripts/refresh.R`.

Raw season files are cached once per immutable revision. Audited ingestion
revalidates snapshots; reconstruction checkpoints skip unchanged event and
reference inputs under the same method fingerprint. Failed games are explicit
in `quality_exceptions` and the season report, not silently repaired. A fatal
season/download failure returns nonzero. Quarantined games can coexist with a
completed audit attempt. The original incremental `backfill.R` remains
available, but use the audited commands above for research-ready processing.
The serial and parallel reconstruction commands are alternatives. Parallel
processing uses isolated season databases and publishes only after all workers
pass integrity checks; it can substantially reduce a full historical rerun.
After the historical caches are populated, `verify_historical.R` checks every
canonical game's method, warehouse integrity, registered file hashes and raw-gap
probes, then writes final verification reports and refreshes Parquet exports.

The scheduled GitHub workflow retrieves licensed SDV and Kaggle archives,
reconstructs, reconciles and reports; it does not scrape NBA/ESPN websites.
Mutable archive references resolve to immutable commits before caching. A
changed independent license disables automatic retrieval for review.
Its warehouse artifact expires after 14 days and
Actions cache is best-effort, so local storage is recommended for durable use.

## Query locally

```r
source('scripts/load.R')
con <- connect_warehouse()
games <- get_player_games('Luka Doncic', seasons = '2024-25', con = con)
offensive_efficiency(games)
get_game_pbp(games$game_id[1], con = con)
get_player_shots('Luka Doncic', '2024-25', con = con)
get_game_possessions(games$game_id[1], con = con)
get_team_lineups('LAL', '2024-25', con = con)
DBI::dbDisconnect(con, shutdown = TRUE)
```

The offline fixture has three games. Add other seasons through ingestion
before querying them. Accent-insensitive lookup supports Luka Dončić;
ambiguous names require a stable player key. Queries never call remote APIs.
Possessions and lineups are published only for games passing their respective
reconstruction gates. Unresolved queries explain which status/exception tables
to inspect. `get_player_salary()` still requires a licensed source.
Effective FG% and approximate true shooting are
computed from local shot/FT totals; DNP and missing-data rules are documented.

## Design, sources and limits

Phase 4 adds **110,420 certified shots across 620 games** from existing licensed
evidence, plus separate R research cohorts and selection diagnostics. Current
totals are **3,641,807 canonical / 3,040,069 certified shots**. No provider was
purchased or called with credentials. See the [Phase 4 results and runbook](docs/phase4/runbook.md),
[provider-value assessment](docs/phase4/provider_assessment.md), and
[research extraction guide](docs/phase4/research_datasets.md).

Phase 3 recovers existing source evidence: **1,203,614 added shot attempts,
five additional possession games, nine additional lineup games and three
additional fully reconciled games**. The warehouse remains incomplete.
See the [Phase 3 report and runbook](docs/phase3/runbook.md),
[season shooting completeness](docs/phase3/shot_completeness.csv),
[component coverage](docs/phase3/reconstruction_completeness.csv), and
[current unresolved games](docs/phase3/unresolved_games.csv).

- [Architecture](docs/architecture.md): transactions, caching and provenance.
- [Data dictionary](docs/data_dictionary.md): table grains and missing values.
- [Source catalog](docs/data_source_catalog.md): coverage, prices and reuse rights.
- [Limitations](docs/limitations.md): gaps and defensive attribution cautions.
- [Sample attribution](data/sample/ATTRIBUTION.md): exact revision and license.
- [Verification report](docs/verification.md): executed checks and data counts.
- [Phase 1 season completeness](docs/season_completeness.md): preserved 2015–16 onward denominators and exceptions; [historical expansion](docs/historical_completeness.md) is reported separately.
- [Reconstruction methods](docs/reconstruction.md): control boundaries, lineup constraints and reconciliation.

DuckDB includes game metadata, player/team boxes, PBP, shot attempts,
reconstructed possessions, five-player stints, minute checks, independent
totals, reconciliation checks and a source inventory. Defender matchups,
contracts and injuries remain reserved schemas.
No unavailable tracking variables are represented as observations. Large
files, databases and secrets stay out of Git. A six-shot matchup alone cannot
establish defensive ability; opponent context and unobserved contributions
remain essential.

Every available season from 2015–16 through the current 2026–27 snapshot is
audited. See the generated completeness report for loaded, quarantined,
reconstructed and independently reconciled counts; these are different
denominators. Large datasets remain local. A clone starts with a three-game
fixture, a 2016 regression game, and ten team/135 player NBA-derived reference rows.

Next milestone: resolve the documented source exceptions and independently
audit a stratified sample of possession boundaries and substitution sequences. Player
impact metrics, Bayesian matchup models, championship models, cap optimization
and a production website are intentionally deferred.
