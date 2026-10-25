# Tracking and supplementary sources — 2026-10-25

No subscription, account or paid request was used. Prices below are USD before
tax, checked on the providers' pages on this date. Actual optical observations,
assigned matchups and defensive responsibility remain unavailable locally.

| Metric | Earliest evidence reviewed | Local status |
|---|---|---|
| Drives/touches | 2013–14 NBA player aggregates in the primary study below | No complete touch/drive feed; 2015–16 release has estimated pre-shot touch time |
| Passing/potential assists | 2013–14 aggregates in the study | No authorized local tracking export |
| Player speed/distance | 2013–14 aggregates in the study | 2015–16 filtered release velocities only; no complete player paths |
| Nearest-defender distance | Licensed local feature release: 2015–16; earliest public aggregate season unverified here | Estimated release geometry; proximity does not assign responsibility |
| Defensive impact at rim | 2013–14 aggregates in the study | Not integrated; definition differs from nearest defender |
| Hustle contests/deflections | NBA says recording started in the 2016 postseason | Not integrated; do not backdate all categories to 2013–14 |
| Matchups/switches/help defense | Earliest metric-specific season unverified | No inferred assignments |
| Shot difficulty | Provider model starts vary and remain unverified | No new model; archetypes and contest-time models excluded from normalized features |
| On/off and five-player lineups | SDV PBP starts 2001–02 | Reconstructed only in games passing current gates; actual admitted seasons in execution report |

The [primary study](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0132894)
documents 2013–14 NBA tracking aggregates, not universal game coverage or a bulk
data license. Its article license does not license NBA trajectories.
[NBA hustle history](https://cdn-uat.nba.com/news/history-hustle-award-winners)
documents the separate hustle start. Dates above are earliest evidence verified
here, not claims of universal first collection.

## Free sources integrated

[Juan Oliver's Shot Features](https://www.kaggle.com/datasets/juanmaoliver/shot-features)
v1 declares the **dataset MIT licensed** in cached Kaggle metadata. It supplies
97,997 records across 631 regular-season games in 2015–16. Attribution credits
Juan Oliver and the SportVU/PBP mirrors named in the raw metadata. No grant is
inferred for downloading upstream raw trajectory mirrors. CSV, metadata,
SHA-256 and physical record ordinals are preserved.

The publisher infers release frames from ball height and filters preceding
movement. Accordingly `tracking_provider_context` and `tracking_provider_estimates`
contain **provider estimates**, not independently reproduced optical observations.
Checks cover native game/season/team identity, period elapsed bounds, binary
outcomes, geometry agreement and broad numeric plausibility. **97,272 context
rows pass**. All **725 overtime rows fail elapsed-time bounds**, remain retained,
and have null standardized metrics. Additional implausible velocities fail
their individual metric checks. The source's overtime elapsed convention needs
review; it is not silently corrected. Uncertainty is `source_missing`.

The frame is a 94×50 foot court, right basket (88.75,25), separate from canonical
shot coordinates. Nearest-player strings remain labels, with no guessed IDs or
rows in `matchup_observations`. Missing event IDs prevent a reliable canonical
shot join. The geometric three-point flag misses corner cases and is not used
as an authoritative shot value. GMM archetypes, spacing and contest-time models
remain raw. This subset is not a complete season denominator.

[BoxScore Lab downloads](https://boxscorelab.com/downloads/) declare **CC BY 4.0**
for 15 CSVs, 2022–23 through the partial 2026–27 season. Attribution: **BoxScore
Lab, boxscorelab.com, data through October 25, 2026**. Build `20261025T1216`
adds separate player season totals, standings and team game results. Counting
fields and modeled ratings/pace remain distinguishable; no estimated rating
is promoted to observed canonical data. Player counts may combine all stints
under the latest team label, including valid 83-game seasons. No player IDs are
guessed. Explicit modern team mappings and unique date/opponent pairs support
comparisons. These feeds share NBA Stats upstream: agreement is **dependent**.
Failed records remain in provider tables and exception CSVs. Downloads change
nightly, so an unavailable cached build is an explicit reproduction limit.
Twenty team-game rows fail the reciprocal home-flag gate because both sides
report `home=False`; no home designation is guessed to promote those rows.
This is a venue-label limitation, not evidence that their counting totals are
necessarily wrong. The earlier complete-season standings claim 1,230 games
each; that publisher claim remains separate from a certified independent
denominator. The active season is partial.

```sh
Rscript scripts/cache_supplementary_sources.R
Rscript scripts/ingest_tracking_features.R
Rscript scripts/ingest_boxscorelab.R
Rscript scripts/check_boxscorelab_stage.R
```

Staging avoids the main writer lock. `scripts/finalize_execution.R` publishes
new provider tables and reports after physical reconstruction. Imports skip
unchanged hashes. Raw/provider feeds stay local and ignored by Git. Datasets
with unknown licenses, including `dansbecker/nba-shot-logs`, were excluded.

## Paid and credential-dependent options

| Priority | Option | Verified access | Incremental value and blocker |
|---|---|---|---|
| 1 | [PBP Stats Tracking](https://tracking.pbpstats.com/) / [membership](https://www.patreon.com/pbpstats/join) | Tracking Access $10/month; $2 supporter is different | Hand-charting and NBA aggregate filters may add distance/dribble/touch context. Login, metric starts, CSV completeness and research/export/retention rights need confirmation. |
| 2 | [BBall Index](https://www.bball-index.com/data-tools-package/) | $5/month or $52.50/year | Role/impact/model benchmarks; modeled lineup tools advertise 2013–14 onward. This does not date every metric or establish bulk CSV/API rights. |
| 3 | [DunkAPI](https://dunkapi.com/pricing) | Free 500 credits/month; $19/10,000; $49/30,000 | ESPN upstream overlaps SDV; [atlas](https://dunkapi.com/docs/atlas) advertises 2003–04+. Some historical boxes are PBP-counted. Credential unavailable; user chose to proceed without it. **Zero authenticated coverage tests run.** |

DunkAPI plays cost 10 credits/call, allowing 50 free calls before pagination.
Documented limits are 60 requests/minute, reduced to 10 below 100 credits.
[Terms](https://dunkapi.com/terms) allow local research/derived outputs while
prohibiting standalone feed redistribution. Advertised coverage was assessed,
not empirically certified. Incremental permitted tracking is a higher priority
than another ESPN subscription.

[Standard PBP Stats](https://pbpstats.readthedocs.io/en/latest/) is useful for
parser methodology and order/lineup comparisons. The parser's code license
does not license upstream data; no blanket bulk-storage grant was established.
Paid pilots require purchase authorization and appropriate data rights. None
is necessary to finish the current free historical reconstruction.
