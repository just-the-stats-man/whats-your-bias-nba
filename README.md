# What's Your Bias? — NBA research warehouse

Reproducible data infrastructure for checking basketball claims with evidence.
The first milestone is a local warehouse, not a player ranking or predictive
model. Original R code is MIT licensed; sample NBA data is separately CC BY 4.0.
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

```sh
Rscript -e "source('scripts/load.R'); targets::tar_make()"
Rscript scripts/ingest.R 2024-25
Rscript scripts/backfill.R 2016 2027
quarto render articles/luka-efficiency.qmd
```

Backfill parameters are **season end years**: 2016 means 2015–16. The default
revision is pinned in `R/sources/sportsdataverse.R`; newer archive revisions
can be selected with `WYB_ARCHIVE_REVISION` for backfill. To update a current
season from the publisher's mutable branch, set `WYB_SEASON=2026-27` in your
environment and run `Rscript scripts/refresh.R`.

Raw season files are cached once per revision. Existing completed games are
skipped. Failed batches are retried game-by-game, and failed games are logged
and excluded. An incomplete season returns a nonzero exit; rerun after an
upstream correction to fill gaps. Reports live in `data/processed/quality/`
and statuses in `ingestion_runs`. Cached archive files have season granularity:
a changed current-season file still requires a complete object download.

The scheduled GitHub workflow retrieves only the CC BY archive; it does not
scrape NBA/ESPN websites. Its warehouse artifact expires after 14 days and
Actions cache is best-effort, so local storage is recommended for durable use.

## Query locally

```r
source('scripts/load.R')
con <- connect_warehouse()
games <- get_player_games('Luka Doncic', seasons = '2024-25', con = con)
offensive_efficiency(games)
get_game_pbp(games$game_id[1], con = con)
get_player_shots('Luka Doncic', '2024-25', con = con)
DBI::dbDisconnect(con, shutdown = TRUE)
```

The offline fixture has three games. Add other seasons through ingestion
before querying them. Accent-insensitive lookup supports Luka Dončić;
ambiguous names require a stable player key. Queries never call remote APIs.
`get_team_lineups()` and `get_player_salary()` report missing sources until
validated data is imported. Effective FG% and approximate true shooting are
computed from local shot/FT totals; DNP and missing-data rules are documented.

## Design, sources and limits

- [Architecture](docs/architecture.md): transactions, caching and provenance.
- [Data dictionary](docs/data_dictionary.md): table grains and missing values.
- [Source catalog](docs/data_source_catalog.md): coverage, prices and reuse rights.
- [Limitations](docs/limitations.md): gaps and defensive attribution cautions.
- [Sample attribution](data/sample/ATTRIBUTION.md): exact revision and license.
- [Verification report](docs/verification.md): executed checks and data counts.

DuckDB initializes 20 related tables. Game metadata, player/team boxes, PBP,
PBP-derived field-goal attempts and substitution descriptions are implemented.
Lineups, defender matchups, contracts and injuries have reserved schemas.
No unavailable tracking variables are represented as observations. Large
files, databases and secrets stay out of Git. A six-shot matchup alone cannot
establish defensive ability; opponent context and unobserved contributions
remain essential.

Local backfill verification loaded 1,314 games from 2024–25 (one upstream
inconsistent game excluded), plus three games each from 2015–16, 2025–26 and
2026–27. The latest verified game date is 2026-10-22. These large datasets
remain local; a clone starts with the three-game fixture. Other historical
seasons are supported by resumable ingestion but have not been backfilled.

Next milestone: complete audited historical backfill and validate possession/
lineup reconstruction against independently permitted reference data. Player
impact metrics, Bayesian matchup models, championship models, cap optimization
and a production website are intentionally deferred.
