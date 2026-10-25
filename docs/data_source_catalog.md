# NBA data source catalog

The [2026-10-25 tracking and supplementary-source assessment](tracking_assessment.md)
updates the audit below, including the limited licensed feature and season-total
imports. The [execution verification](execution_verification.md) records what was
actually integrated; assessed providers are not automatically connected feeds.

Reviewed 2026-10-23. Prices are USD and exclude tax. **Unknown** means not
verified, not free or permitted. No subscriptions were purchased. Public
accessibility and open-source client code do not grant data redistribution rights.

| Source | Data / historical scope | Updates / method | Price verified | Limits, rights, automation / reproducibility decision |
|---|---|---|---|---|
| [SportsDataverse hoopR NBA archive](https://github.com/sportsdataverse/hoopR-nba-data) | Schedules, player/team boxes, PBP, shots; publisher advertises 2002–present | Publisher batch files; GitHub raw Parquet and release assets | $0 | [Publisher CC BY 4.0](https://github.com/sportsdataverse/hoopR-nba-data/blob/main/LICENSE.md). Attribution and change notices required. Automated archive downloads enabled; publisher cadence/SLA not guaranteed. Selected working source; upstream rights not independently audited. |
| [hoopR](https://github.com/sportsdataverse/hoopR) | R loaders and direct NBA/ESPN clients; history varies by endpoint | R package / release loaders | $0 code | Client license is separate from feed rights. Use licensed archive, not automatic activation of every scraper. Schema evolves. |
| [NBA Stats / nba.com](https://api-hub.nba.com/termsofuse) | Traditional/advanced boxes, PBP, shots, lineups, tracking, matchup summaries; varies by feed/era | Web/API, in-game and postgame | Public viewing $0; bulk license unknown | No public API SLA; endpoint blocks/timeouts possible. Terms restrict reuse; automated ingestion/redistribution not established here. Disabled pending permission. |
| [ESPN](https://www.espn.com/nba/) | Schedules, boxes, PBP, rosters; historical depth endpoint-dependent | Public JSON endpoints; live updates | Viewing $0; no public licensed API price verified | Undocumented schemas, no public rate/SLA guarantee. [Disney terms](https://disneytermsofuse.com/) apply. Direct automation disabled; use archive publisher's grant. |
| [Basketball Reference](https://www.basketball-reference.com/) | NBA historical player/team tables, game logs, selected salaries | Web tables, daily corrections | Viewing $0 | [Bot policy](https://www.sports-reference.com/bot-traffic.html) and [data-use policy](https://www.sports-reference.com/data_use.html); rate limits do not constitute a bulk redistribution license. No scraping adapter. Useful manual cross-check. |
| [Stathead](https://faq.sports-reference.com/portal/en/kb/articles/subscription-plans) | Searchable historical basketball records; finder coverage varies | Subscription web search/export | $9/month or $80/year one sport; $16/month or $160/year all sports | Manual research option within budget. Subscription is not bulk API/automation permission; same SR rights constraints. |
| [pbpstats.com](https://www.pbpstats.com/) / [parser](https://pbpstats.readthedocs.io/en/latest/) | Possessions, lineups, shot zones, on/off; NBA coverage feed-dependent | Documented API examples and Python parser | Public tools $0; paid/license quote not verified | No verified service rate/SLA or blanket redistribution license. Parser repairs some event order issues. Evaluate permission before ingestion; promising lineup validation reference. |
| [Public PBP archives](https://github.com/sportsdataverse/hoopR-nba-data/tree/main/nba/pbp) | Season PBP files, varying missing games | Static/batch archive | $0 selected archive | Pin revision and hash; archive presence does not prove complete events. Selected SDV archive license above; other archives need individual review. |
| [Public GitHub shot project](https://github.com/toddwschneider/nba-shots-db) | Shot ingestion code / historical shot datasets | Repository scripts | $0 code | Project reports discontinued NBA shot-log availability. Do not equate code license with upstream tracking-data rights. No ingestion enabled. |
| [Kaggle datasets](https://www.kaggle.com/datasets/wyattowalsh/basketball) | Historical SQLite / game and player datasets; uploader-dependent | Kaggle download/API, update cadence varies | Typically $0 downloads; account may be needed | [Kaggle terms](https://www.kaggle.com/terms) and dataset-specific license apply. Exact current dataset license/coverage not verified; not selected. Uploader rights and revisions must be checked. |
| [NBA injury reports](https://official.nba.com/nba-injury-report-2026-27-season/) | Timestamped PDF snapshots for current season and linked archives | Published repeatedly during day | Viewing $0 | Preserve report time and revisions; no inference of absence from missing report. Bulk automation permission unresolved; disabled. |
| [NBA lineup/tracking pages](https://www.nba.com/stats/) | Lineups, matchup aggregates, tracking-era metrics; not public optical trajectories | Website / NBA Stats endpoints | Viewing $0; licensed feed unknown | Provider attribution differs from defensive responsibility. No licensed automated adapter; unavailable warehouse fields remain empty. |
| [Spotrac](https://www.spotrac.com/nba/) | Contracts, options, payroll and cap tables; historical access varies | Website, premium products | Current premium price **not verified**; pricing page inaccessible | Terms/automation grant could not be verified. No scraping; request permitted export/API terms before use. |
| [HoopsHype salaries](https://hoopshype.com/salaries/) | Salary tables and future commitments, archive depth varies | Web tables, transaction updates | Public viewing nominally $0; licensed export price unknown | Page inaccessible during review; automated reuse and redistribution unverified. Disabled. |
| [Basketball Reference salaries](https://www.basketball-reference.com/contracts/) | Player/team reported salaries, selected historical tables | Web tables | Viewing $0 | Same SR policy restrictions. Salary is not necessarily cap hit, guarantee or cash paid. Manual cross-check only. |
| [NBA cap announcements](https://www.nba.com/news/nba-salary-cap-2026-27-season) | Official annual cap/tax thresholds, not player contracts | Annual news release | $0 viewing | Reliable citation for published thresholds. Manual reference; no news scraping pipeline. |
| [Public contract datasets](https://www.kaggle.com/datasets) | Uploader CSVs, inconsistent options/guarantees/history | Static releases, irregular | Often $0; no selected verified license | No vetted canonical contract dataset selected. Require season definitions, provenance and specific redistribution license before import. |
| [SportsDataIO](https://sportsdata.io/developers) | NBA boxes, injuries, lineups, PBP; [historical access](https://sportsdata.io/help/data-rights-and-licensing-questions) contract-dependent | Official keyed REST; commercial real-time, other access tiers | Trial available; production quote required. Exact current hobby price not verified | Endpoint call intervals documented; storage/display depend on agreement. Do not treat trial responses as verified production data; no purchase/integration. |
| [Sportradar](https://sportradar.com/media-tech/data-content/sports-data-api/) | Official commercial NBA game/event feeds, historical coverage contract-dependent | Keyed API / push; real-time | 30-day trial advertised; production quote required | Quotas and redistribution contractual. No assumption it fits $50 budget. No purchase. |
| [BALLDONTLIE](https://docs.balldontlie.io/) | Teams/games/players free; paid stats, shots, lineups, contracts. PBP from 2025 season per docs | Official keyed REST; event updates | $0 free; ALL-STAR $9.99/month; GOAT $39.99/month | 5/60/600 requests per minute respectively. [Terms](https://www.balldontlie.io/terms.html) govern storage/publication and restrict redistribution. Within-budget paid candidate; verify intended article/output rights before subscribing. |

## Recommendations

The reconstruction milestone connects [Eoin Moore's NBA dataset](https://www.kaggle.com/datasets/eoinamoore/historical-nba-data-and-player-box-scores)
through Kaggle's public dataset API. `TeamStatistics.csv`, `PlayerStatistics.csv`
v524 and their dataset metadata
were downloaded on 2026-10-23. Official metadata declares **CC0: Public Domain**;
price $0, no paid credentials. NBA-derived historical team/game totals include
regular season, playoffs, play-ins and Cup finals. This is distinct from the
ESPN feed, not guaranteed independent observation of the underlying event.
Cadence is publisher-controlled; no SLA/fixed download quota was verified.
Raw CSV, metadata and SHA-256 are preserved. Independent player records supply
the player-turnover benchmark because the reported team turnover field changes
definitions across eras. Unknown or duplicated player observations do not
become verified zeros. Ten team rows, 135 player rows and derived
diagnostics are committed. The publisher declaration supports this archive
integration; underlying NBA rights are not independently audited. Automated
refresh checks the license before selecting a new version and stops on change.

The [SDV raw JSON archive](https://github.com/sportsdataverse/hoopR-nba-raw)
publishes [CC BY 4.0](https://github.com/sportsdataverse/hoopR-nba-raw/blob/main/LICENSE.md).
Gap probes pin `e2c40720c72a98f427f8964deba8dd0e22ff1303`, preserve JSON bytes
and log availability. Empty play lists and unchanged erroneous original totals
cannot be repaired by guesses. This shares ESPN provenance, so is not the
independent totals reference.

Start at $0 with the pinned SDV archive, local DuckDB and bundled attributed
fixtures. Treat missing/invalid games as research gaps. For manual historical
cross-checks, Stathead is inexpensive but does not replace a warehouse feed.
BALLDONTLIE GOAT is a documented $39.99/month candidate for contracts/lineups,
subject to a rights and coverage check. SportsDataIO/Sportradar need quotes;
restricted defender assignments may require a separate advanced tracking
agreement beyond this budget. No free public feed was verified to provide
possession responsibility, help and switching ground truth.

This is an evaluated candidate inventory, not a claim that every provider
was successfully connected. SDV and the versioned Kaggle team/player archive
are enabled; direct NBA/ESPN website scraping remains disabled.
