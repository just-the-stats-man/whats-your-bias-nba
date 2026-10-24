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
conservation, FG/3P/FT/turnover totals, control continuity, or available
independent totals disagree. No probability model fills missing events.

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

Eoin Moore's CC0-published Kaggle `TeamStatistics.csv` v524 is NBA-derived,
distinct from the ESPN-derived SDV archive. Raw CSV, metadata, source version
and SHA-256 are retained. `config/team_crosswalk.csv` maps the 30 franchises.
Matching requires an exact date, home/away pair, and a unique reciprocal
reference game. Scores are never matching keys; there is no fuzzy matching.

Checks compare final scores and both teams' FGM/FGA, 3PM/3PA, FTM/FTA, assists
and player turnovers. Team-inclusive turnovers additionally validate PBP/box
counts. Missing values do not pass. Unmatched games, reference-only games and
contradictions have separate report categories. Neither feed is assumed
complete or error-free; agreement is not proof of independent ground truth.

An invalid/missing ESPN team box may be replaced by an **entire** uniquely
matched NBA-derived team record, attributed to its dataset. It must still
pass the player/schedule/PBP gates. Individual cells are never adjusted to
force a score identity. `reconciliation_checks.independent=FALSE` marks checks
against the same reference record used for recovery. Independent ESPN
schedule/PBP comparisons remain possible; recovered games are counted
separately. Raw ESPN records and original failures survive.

Contradictory reference updates immediately withdraw published derived rows.
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

The audit defaults to 2015–16 through the pinned 2026–27 snapshot. Optional
numeric arguments select individual end years, e.g. `2016 2025` selects two
seasons. Reconstruction accepts season labels and resumes unchanged games.
`scripts/sample.R` and `targets::tar_make()` use small offline fixtures.

See [season completeness](season_completeness.md) for actual counts.
Completed processing, canonical data, reconciled reconstruction, and agreement
with an independent source are different completeness measures.
