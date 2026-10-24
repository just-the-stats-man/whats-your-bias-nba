# Research limitations and interpretation

The initial offline deliverable contains three 2024–25 games, not all seasons.
Backfill support starts at 2015–16; archive coverage is not a completeness
guarantee. Only completed regular-season and playoff games are selected.
Preseason, All-Star showcases and ongoing games are excluded. ESPN IDs 1–30
are the franchise allowlist for the covered era; expansion needs an explicit
policy update. The NBA Cup final may be classified
by the provider alongside other regular-season games; filter the raw schedule
metadata when constructing official season totals. ESPN and NBA IDs differ.

Box scores and PBP are provider-attributed records of observed outcomes.
Some older archives lack points_attempted; these retain PBP but do not
populate derived shots, rather than guess field-goal versus free-throw values.
Field-goal attempts are selected from provider shooting events with 2/3 points
attempted; free throws remain PBP events and box-score counts. Shots are not
nearest-defender observations. Names and participant roles can be incomplete.
We preserve descriptions without inferring defender responsibility.

| Variable family | Status |
|---|---|
| Points, FGM/FGA, FTM/FTA, AST, TOV | Provider-attributed, ingested |
| Period, clock, play descriptions | Provider-attributed, ingested |
| Shot coordinates | Provider-attributed, incomplete and uncalibrated |
| Shooting fouls, free throws drawn | Descriptions available; no validated attribution extractor |
| Possession outcomes, lineup/on-off | Require validated possession/stint reconstruction |
| Primary defender, help, switches, nearest defender | Unavailable |
| Potential assists, advantage-creating passes | Unavailable |
| Expected shot value, opponent-adjusted effects | Model-estimated, deliberately deferred |
| Salaries, options, cap hits, injuries | Schema reserved; no licensed ingestion yet |

A claim of 1-for-6 shooting describes six selected attempts, not total
offensive contribution. It can omit free throws, assists, turnovers, switches
and help defense. Matchup attribution depends on provider definitions; nearest
defender, assigned primary defender and responsibility for an entire possession
are different variables. Selection and opponent context confound comparisons.
Even under independent equal-quality shots, six attempts have high sampling
uncertainty. A binomial interval would describe that simplified experiment,
not establish defensive ability or causality. No ranking/model is included.

Validation checks internal consistency, not truth of the feed. Some seasons
can fail because of upstream missing or conflicting data; reports remain local.
No access controls are bypassed. The CC BY publisher declaration is not an
independent audit of upstream rights. This project does not grant licenses to
NBA trademarks, imagery, videos or restricted tracking feeds.
