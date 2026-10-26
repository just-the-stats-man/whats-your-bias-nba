# Phase 4 provider-value audit

Reviewed **2026-10-25**. Planning ceiling: approximately **$50/month total**;
no purchase, trial or credit-consuming request has been authorized or made.
Prices below are advertised USD prices, before unverified taxes. Counts are
warehouse bounds or provider claims, not measured new certified coverage.

| Rank / decision | Source and advertised billing | Marginal value and limits |
|---|---|---|
| 1 — implement existing-evidence recovery | Already licensed SDV / NBA observations; $0 new cost | An explicit terminal-score defect identifies 822 candidate games / 146,595 recorded attempts across 2019–20 through 2023–24. This is an upper bound, pending full shooting/identity checks; no new observations are invented. |
| 2 — conditional one-month pilot | PBP Stats Tracking Access: $10/month; $2 Supporter is a separate tier | Potential tracking context unavailable locally. CSV export is advertised but requires login. Exact seasons, columns, retention, modeling/publication rights and automated/bulk access remain unverified. Purchase only after rights confirmation and explicit approval. |
| 3 — free-credit comparison first; defer purchase | DunkAPI: free 500 credits/month; Starter $19/month / 10,000 credits; Pro $49/month / 30,000 | Documented PBP/shot coverage starts 2003–04. No live sample or key exists here. Additional interface is not independent verification; likely shared ESPN lineage is an inference from identifier conventions and descriptions, not a provider attestation. |
| 4 — free benchmark / investigate rights | Standard PBP Stats: public website/API; no subscription advertised for ordinary API docs | NBA summaries from 2000–01, reconstructed possessions/lineups and modeled shot quality. Counts exclude some heaves; definitions differ. Public access and MIT parser code do not establish blanket redistribution rights for the underlying NBA observations. |
| 5 — defer | BBall Index Data & Tools: $5/month or $52.50/year advertised | Useful player/context/model benchmarks, rather than missing event evidence. API/bulk CSV, retention and publication permissions are unverified. The advertised lineup creator reaches 2013–14; that does not establish every metric's historical extent. |
| 6 — defer for historical recovery | BALLDONTLIE NBA GOAT: $39.99/month; ALL-STAR $9.99 lacks plays/shot charts | Official docs limit PBP to seasons beginning in 2025. It cannot fill early-2000s event gaps. No paid trial was started. Raw storage/publication rights require separate terms review before ingestion. |

Primary evidence: [Tracking site](https://tracking.pbpstats.com/),
[Patreon tiers](https://www.patreon.com/pbpstats/join),
[DunkAPI pricing](https://dunkapi.com/pricing), [coverage atlas](https://dunkapi.com/data),
[PBP Stats](https://www.pbpstats.com/), [public API docs](https://api.pbpstats.com/docs),
[BBall Index package](https://www.bball-index.com/data-tools-package/),
[membership prices](https://www.bball-index.com/become-a-member/),
[BALLDONTLIE official documentation](https://docs.balldontlie.io/).

## What Tracking could add

| Measurement | Published granularity / epistemic category | Earliest / latest verified service season | Identifier / export evidence |
|---|---|---|---|
| Closest-defender shooting | Filtered shooting counts by distance bucket; NBA-reported context, not a responsible-defender assignment | Unknown / unknown | Game logs and CSV interface advertised; actual ID columns need pilot |
| Dribbles before shot | Filtered shooting counts by dribble category | Unknown / unknown | Same export uncertainty |
| Touch duration before shot | Filtered shooting counts by holding-time category | Unknown / unknown | Same export uncertainty |
| Contested/wide-open shooting | Context buckets; hand-tracked wide-open three-point labels are a separate sample | Unknown / unknown | Individual hand annotations exist; linkage/completeness not verified |
| Shot difficulty / making | Derived or modeled output; model definition must be inspected | Unknown / unknown | Login required; schema unknown |
| Offensive/defensive matchups | NBA-derived team-opponent game logs and season totals advertised | Unknown / unknown | Individual defender responsibility is not established |
| Lineups, on/off, possessions | Standard PBP Stats supplies reconstructed/aggregated context | Standard site says 2000–01 onward; tracking-service extent unknown | Standard API uses NBA IDs; tracking export IDs need confirmation |

The public site describes NBA Stats feeds plus hand annotations. It does not
establish individual-shot optical distances for every attempt. A bucket such as
2–4 feet must remain an interval/category; it is not an observed 3-foot value.
Aggregated filter rows cannot be expanded into invented individual shots.
No raw optical trajectories, full defender assignments or universal historical
coverage have been verified. See the [publisher's description](https://tracking.pbpstats.com/).

Before a $10 pilot, obtain confirmation of: exact metric/season coverage;
export row unit and ID dictionary; manual CSV limits; authorized automation;
local retention after cancellation; statistical modeling; publication of
derived results; attribution and raw redistribution restrictions; and whether
all available history is included. The public login redirect was respected.
No tracking API or bulk entitlement is assumed from membership.

## DunkAPI pilot and economics

The documented `get_plays` request accepts one game, `limit=1000` and offset
pagination. It costs 10 credits per call; boxes cost 5. A conservative
**20-game pilot capped at two PBP pages plus one box per game costs at most
500 credits**, fitting the advertised free allowance. Select 2003–04,
2015–16, modern classification failures and missing-PBP games. Stop at the cap
and mark truncated games unresolved. Never assume all full games fit one page.
See [PBP docs](https://dunkapi.com/docs/get-plays) and
[publisher coverage caveats](https://dunkapi.com/data/nba-play-by-play).

Compare normalized event identities, text, period/clock, actor IDs, outcomes,
FT/FG classes and locations against the pinned local feeds. Measure missing
events, corrected values and newly passing games separately from duplicate
records. Provider claims do not establish useful marginal rows. Publication
remains behind all warehouse gates. Chart exports are capped and expected
points are estimated; see [shot-chart docs](https://dunkapi.com/docs/get-shot-chart).

For a targeted cohort of N games and P PBP pages per game, budget
N × (10P + 5) credits including one box. At Starter's included-credit unit
price, this is a scenario cost of $0.0285/game at P=1 or $0.0475 at P=2,
provided the allowance is fully used; it is not an actual per-request invoice.
If only K games genuinely recover, subscription cost per recovered game is
$19/K; it is undefined when K=0. The purchase decision must use measured K,
not this upper bound. Wallet/overage charging must remain disabled or outside
the explicitly approved credit cap. No live integration is yet validated.

Current [DunkAPI terms](https://dunkapi.com/terms) permit storage, derivation,
research/model training and use inside one's product; standalone data/feed
redistribution is restricted. They also describe continued internal use of
lawfully stored data after account closure. New-account terms were updated
October 18, 2026; older accounts have a transition date and must check their
accepted version. Upstream rights and field limitations still apply. We will
not commit paid raw responses or assume this grants an independent source.

## Spending recommendation

Spend **$0 now** while the existing-evidence pilot and offline infrastructure
are completed. The highest-value *conditional paid pilot* is one month of
Tracking Access at **$10**, after rights/coverage confirmation and explicit
approval. DunkAPI's free allowance should establish incremental value before
a $19 plan. BBall Index is a later $5 benchmark option, not a shot-recovery
purchase. Tracking + Starter + BBall Index would advertise $34/month before
tax, but there is no reason to activate all three now. Pro alone advertises
$49 and leaves no meaningful room for other subscriptions under the ceiling.

Recurring membership may be needed to access a site's tools or new releases;
lawful retention after cancellation is provider-specific. It remains unknown
for Tracking/BBall Index. These are data-rights questions, not assumptions that
can be resolved by buying first. No email or provider message has been sent.
