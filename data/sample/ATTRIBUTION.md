# Sample data license and provenance

`independent_player_rows.csv` contains 135 corresponding player records from
the same Kaggle release's `PlayerStatistics.csv`, under the CC0 publisher
declaration below. They establish player-turnover sums independently of ESPN
and test historical/current team-total conventions. Values are not adjusted
to match another provider.

`historical_2016.rds` is an additional single-game regression fixture from the
same SDV revision/license below: game 400878160, Cleveland–Golden State,
2016-06-19. It filters all four archive tables into one RDS bundle. It retains
the source's zero-valued made-FT annotations and putback/rebound ordering so
the historical parser is tested against those real source characteristics.

Data: hoopR.nba authors, [hoopR-nba-data](https://github.com/sportsdataverse/hoopR-nba-data).
License: [Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/).
Publisher declaration: [LICENSE.md](https://github.com/sportsdataverse/hoopR-nba-data/blob/13f2e6ac8aed3cb6cfea6e81a0db088006357e95/LICENSE.md).
Upstream statistical provider: ESPN. No endorsement is implied.

Retrieved 2026-10-23. Revision: `13f2e6ac8aed3cb6cfea6e81a0db088006357e95`.
Files were filtered to three games featuring Luka Dončić, converted from
Parquet to RDS, and bundled for offline reproduction. These are real data,
not synthetic statistics. `scripts/make_sample.R` reproduces extraction.
`bundle.rds` includes the same four datasets plus source URLs and revision.
The ingestion hash identifies the actual local fixture bytes; it does not
claim to be the original full-season file hash.

The archive publisher's license is the basis for this integration; we have
not independently established rights to every upstream contribution.
Recheck publisher terms before expanding public redistribution. Large raw
files remain local and ignored by Git. MIT does not relicense these data.

`independent_team_totals.csv` contains ten filtered real team rows from Eoin
Moore, [NBA Dataset: Box Scores and Stats](https://www.kaggle.com/datasets/eoinamoore/historical-nba-data-and-player-box-scores),
version 524, `TeamStatistics.csv`, published under CC0 1.0 (verified through
Kaggle's official dataset metadata on 2026-10-23). Upstream: NBA.com.
It is independent of the ESPN-derived fixture for reconciliation purposes;
independence of statistical providers does not imply independent observation
of every underlying sporting event. Filtering and CSV serialization are the
only fixture modifications. Publisher grants are not an independent audit
of upstream rights; no direct NBA/ESPN scraping is performed.

# Phase 3 regression excerpts

`phase3_recovery_cases.rds` contains normalized, unmodified source-input excerpts
for ESPN games `220215013` and `400974774`, taken from the already authorized
SportsDataverse archive. Each case carries its exact dataset manifests, source
URLs, revisions, SHA-256 values and source attribution/license records. These
small regression fixtures retain the original event order, descriptions, IDs,
box records and flags. They reproduce a reversed numbered FT trip and a
substitution whose native actor fields encode the wrong role. The test applies
an audited derived projection; the fixture does not contain a balancing event
or an invented participant. Archive reuse follows its existing CC BY 4.0
attribution; see the original SportsDataverse attribution above. Fixture SHA-256:
`1672e8118c01d4809e96a066d490232955990ab373d78cf7a965641902801cfe`.
