# Possession and five-player lineup reconstruction

These are reproducible reconstructions from provider events, not optical
tracking or defender assignments. The method fingerprint hashes the parser,
normalizer, reconciliation and reconstruction writer. Each game records its
event dataset and independent-reference signature. Changed inputs invalidate
the checkpoint; canonical input replacement invalidates derived tables.

## Possessions

Events retain exact provider IDs and order. A possession begins from evidence
of offensive control and closes on a made field goal, a made final ordinary
free throw, a turnover, a defensive rebound, a resolved held-ball change, or
the period boundary. Offensive rebounds continue it. Made baskets and same-clock
ordinary 1-of-1 and-one attempts stay together. Missed final free throws wait
for a rebound or another resolved ending. Dead-ball rebounds between ordinary
free-throw attempts do not transfer control.

Technical, flagrant, clear-path and other explicitly retained-possession free
throws are in `non_possession_points`; they never manufacture another
possession. Possession points **plus these separately attributed points** must
equal both final scores. Possession-only points are not all offensive production.

The parser handles a verified same-clock jump-ball/linked lost-ball turnover
dependency without rewriting raw order. The turnover's losing team must be
opposite the jump winner, and its stealing participant must match a jump
contestant. It applies the turnover control state before the award, records a
warning with both IDs, and does not count two changes. Other unexplained
changes, unresolved held jumps and ambiguous team rebounds fail closed.
Challenges, reversals and incomplete feeds are not silently repaired.

Every FG attempt, ordinary FT and turnover must have one possession assignment.
Jump awards are neutral annotations. Pure administrative tails without
observed offensive activity do not create a possession. Counts follow this
observable-control convention; they do not claim to reproduce every NBA or
PBPStats convention, particularly heave/short-period rules. Time columns are
elapsed seconds within a period; zero-duration same-clock possessions are
possible. Regulation periods are 720 seconds, overtime periods 300.

A game is withheld from `possessions` if clock/period coverage, scoring
conservation, available FG/FT/turnover totals, control continuity, or available
independent totals disagree. No probability model fills missing events.

Some historical records encode a made NBA FT with scoreValue=0. The explicit
made-FT event contributes its rule-defined one point; the original field stays
unchanged. Made FG values use explicit scoring values. Missing attempt values
are classified only by explicit point annotations or unambiguous shot types;
an unspecified missed jumper remains unknown. Distance is not used to guess.
A historical PBP 3PA check can therefore be **unavailable**, distinct from
pass/fail, in `pbp_reconciliation_checks`. That missing annotation alone does
not invalidate control or lineup reconstruction. Independent box-level 3PA
comparison still runs; box totals never allocate unknown attempts.

A documented source-order correction handles three consecutive events: a
missed FG, a made putback, and the same shooter's same-clock offensive rebound.
The rebound links back to the made basket's possession and cannot start a
phantom possession. Raw order stays unchanged; a causal warning records the
IDs. Other rebound ambiguities remain errors.

## Five-player stints

The first period requires five explicit provider starters per team, consistent
with event evidence. Later starters resolve from each player's first live
event/substitution: a first entry implies initially off court; first
activity/exit implies initially on. A five-player solution is accepted only
when uniquely determined. The previous quarter's ending five is not carried
across a break.

Substitutions use explicit in/out participant IDs. Missing identities, exits
while absent, duplicate entries, unknown live participants, contradictory
starters and ambiguous initial fives reject the game. Bench technical-foul or
ejection references are not on-court evidence. No name-only guesses occur.

Stints require five unique players and complete period coverage without gaps
or overlaps. Player seconds must agree with published box precision: integer
minutes allow 60 seconds (rounding versus truncation is unspecified), decimal
minutes 1.01 seconds, explicit DNP rows zero. These bounds test consistency
with coarse records, not exact playing-time truth. A full game's lineups are
withheld if any period or minute check fails. Resolved-team-period counts
remain for diagnosis; partial stints are not published as complete coverage.

## Independent reconciliation and recovery

Canonical player totals must sum to their team record for FGM/FGA, 3PM/3PA,
FTM/FTA, assists and player turnovers, in addition to points. Unknown playing
player values cannot pass this aggregate gate. Existing warehouses receive
the same check before reconstruction, refresh and completeness reporting;
conflicting games and their derived rows are withdrawn while raw data,
manifests and diagnostic history remain intact.

Reconstruction entrypoints also revalidate cached quarantines under the current
quality gate. A game is readmitted only if its complete normalized source
records pass that gate; prior failures and normalization notes are retained.
This prevents superseded validation failures from becoming permanent gaps.
Readmission does not certify possessions or lineups: their separate gates still
run, and unknown event actors remain unknown. Completeness reporting alone does
not readmit games.

An aggregate difference is not automatically a source error. From 2025–26,
qualifying missed heaves count against team attempts without affecting
individual attempts ([NBA explanation](https://www.nba.com/news/nba-heaves-rule-change-early-results)).
The current gate requires explicit compatible provider evidence before such
a residual can be accepted. It does not infer team-only attempts from a
score difference, distance alone or a desired box-score total; otherwise the
game remains quarantined. Provider-specific player efficiency figures require
this accounting caveat when comparing eras.

Eoin Moore's CC0-published Kaggle `TeamStatistics.csv` and `PlayerStatistics.csv` v524 are NBA-derived,
distinct from the ESPN-derived SDV archive. Raw CSV, metadata, source version
and SHA-256 are retained. `config/team_crosswalk.csv` maps the 30 franchises.
Matching requires an exact date, home/away pair, and a unique reciprocal
reference game. Scores are never matching keys; there is no fuzzy matching.

Checks compare final scores and both teams' FGM/FGA, 3PM/3PA, FTM/FTA, assists
and player turnovers. NBA's reported team turnover field changes conventions
across eras: some records include team turnovers, others do not. The independent
player benchmark is summed directly from the independent player file, never
selected by whichever total matches ESPN. Duplicate/missing observations do
not become verified zeros. Reported values remain available; normalized
records link to both raw parents through `dataset_dependencies`.
Some independent player rows omit their team ID. A missing ID resolves only
through a unique record in the same provider's team file sharing the game ID,
home/away flag, team name and opponent name. Present conflicting identifiers
are not overridden. No statistic is filled from this match. Resolution counts
and affected games are recorded; ambiguous identity or missing/fractional
turnover observations leave the benchmark unavailable.
Team-inclusive turnovers additionally validate PBP/box
counts. Missing values do not pass. Unmatched games, reference-only games and
contradictions have separate report categories. Neither feed is assumed
complete or error-free; agreement is not proof of independent ground truth.

An unavailable independent metric is not a contradiction. Internally
reconciled possessions and lineups can be published when every available
comparison agrees; full independent certification still requires every
requested reference metric. Actual contradictions withdraw publication.

When an ESPN team-inclusive turnover field is absent, its value remains NULL.
The observed PBP count may instead be compared directly with an explicit,
uniquely matched independent total. `pbp_reconciliation_checks` retains the
original `box_value` alongside `benchmark_value`, `benchmark_type`,
`benchmark_dataset_id` and `benchmark_game_id`. A missing or contradictory
required benchmark withholds reconstruction. Reference refresh rechecks these
direct comparisons immediately; checkpoints include their actual values.

An invalid/missing ESPN team box may be replaced by an **entire** uniquely
matched NBA-derived team record, attributed to its dataset. It must still
pass the player/schedule/PBP gates. Individual cells are never adjusted to
force a score identity. `reconciliation_checks.independent=FALSE` marks checks
against the same provider used for recovery, even across snapshots. Independent ESPN
schedule/PBP comparisons remain possible; recovered games are counted
separately. Raw ESPN records and original failures survive.

Contradictory reference updates immediately withdraw published derived rows.
The normalized reference scope is replaced on snapshot selection; withdrawn
reference records are not silently carried forward. Older raw files and
manifests remain preserved. Fully reconciled season counts exclude games with
reference-dependent box scores, even when all reported values agree.
Missing PBP/player statistics and ambiguous identities remain unresolved.
Selected gaps were also checked in the licensed raw JSON archive: empty play
lists and unchanged inconsistent original totals do not permit safe repair.

## Reproduction

```sh
Rscript scripts/audited_backfill.R
Rscript scripts/reconstruct.R
Rscript scripts/report_completeness.R
Rscript scripts/test.R
```

For a full recomputation, `Rscript scripts/reconstruct_parallel.R` runs isolated
season workers (default four; set `WYB_WORKERS` to change the limit). The parent
keeps the warehouse write lock, freezes input Parquet snapshots, and publishes
all selected seasons in one transaction after every worker passes integrity.
The workers use the same parser as the serial command; real-fixture tests
compare their possession, lineup, minute, benchmark and status outputs.

The audit defaults to 2015–16 through the pinned 2026–27 snapshot. Optional
numeric arguments select individual end years, e.g. `2016 2025` selects two
seasons. Reconstruction accepts season labels and resumes unchanged games.
`scripts/sample.R` and `targets::tar_make()` use small offline fixtures.

See [season completeness](season_completeness.md) for actual counts.
Completed processing, canonical data, reconciled reconstruction, and agreement
with an independent source are different completeness measures.
## Phase 3 scoped recovery

The original physical engine and its four-file Phase 2 fingerprint remain
unchanged. A versioned working projection can reorder a complete, uniquely
numbered same-clock ordinary FT trip, recover a missing explicit jump winner,
and assign substitution roles from exact unique full roster names in observed
“enters the game for” descriptions. A historical actor field can contain the
outgoing player in the incoming slot; only IDs belonging to that explicitly
named pair are eligible for role correction. An unrelated observed ID is a
conflict. Unicode transliteration and trimming whitespace/sentence termination
are explicit; no fuzzy aliases or missing names are guessed.

FT trips require unique complete ordinals, one shooter/team/period/clock, no
intervening live ball event and no substitution involving the shooter. Native
order and descriptions remain untouched. Duplicate trips, retained FTs, gaps
and equally plausible sequences stay unresolved. A roster with wholly missing
starter flags can use the same unique first-participation/exit/entry constraints
as later periods; explicit contradictory flags are retained. This last rule is
tested but did not add a production game in the screened cohort.

Every result must still pass the original control, scoring, event totals,
five-member, participation, time coverage, reference and player-minute gates.
The source precision bounds are unchanged. The 2,002-game scope includes
affected certified games for regression checking. Publication only adds failed
components that now pass; it never replaces previously certified possessions or
lineups. Component-level methods and immutable registered RDS results identify
the derivation; original failed statuses/checks and exceptions remain available.

The Phase 3 commands and limitations are in [the runbook](phase3/runbook.md).
Legacy full-rebuild commands above reproduce the earlier engine; they should
not be used to overwrite a Phase 3 warehouse. This phase does not infer absent
substitutions, team-rebound intent, optical tracking or defender assignments.
