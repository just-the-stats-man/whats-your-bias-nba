# Phase 3 recovery strategy

Baseline: `c391b10`, 36,426 canonical games, 2,180,766 possessions,
642,427 five-player stints and 9,666 fully reconciled games. Before changing
reconstruction logic, all 299 assertions, all 85 integrity checks, all 36 exact
Phase 2 snapshot tables and all 9,645 registered input hashes passed.
The frozen export directories are read-only inputs to this phase.

## Priority and affected scope

1. **Shot extraction — high impact, low risk.** The existing extractor requires
   `points_attempted` to be 2/3. That field is absent or mostly null in several
   modern schemas even when explicit FG flags, outcomes, actors and locations
   exist. For 2023–24, canonical PBP has 233,588 flagged FGs, only 1,430 annotated
   FGs, against 233,601 canonical box FGAs. There are genuine event/count gaps as
   well as a filter defect; the discrepancy is not filled to a target count.
   Some miss descriptions also omit two/three labels. Existing NBA observations
   provide additional explicit values through unique game/team/player/period/
   clock/outcome links; strict full-name/box-stat identities and one-to-one
   matches are required. No value is inferred from distance or coordinates.
   Six representative historical/modern seasons were staged before broad use.
   The rollout covers 26 cached PBP seasons; it never reingests whole game boxes
   or reruns physical reconstruction. Only fully count-matched, verified-ID
   groups can add canonical rows. Other observed candidates remain noncertified.
2. **Possession ordering/parsing — scope after diagnostic screening.** Cached
   exceptions include offensive-control changes in 12,094 games and PBP/box
   findings in 8,876 games. These categories overlap and can retain historical
   reference diagnoses; they are screening counts, not promises of recovery.
   Current critical PBP checks and reference comparisons narrow the pilot to
   games with consistent recorded totals. Representative source excerpts show
   same-clock `2 of 2` free throws placed before `1 of 2`, plus ambiguous team
   rebounds and held balls. Numbered complete trips can support a deterministic
   derived order; missing events and ambiguous sequences cannot be repaired by
   selecting whichever order happens to pass. Raw order is preserved.
3. **Lineups — evidence constrained.** Cached minute-bound findings affect
   5,416 games and incomplete time coverage 4,095 games, with overlap. Examine
   missing starter flags, period evidence and same-clock substitution chains
   before treating these as recoverable. Use exact membership, participation,
   clock and original minute bounds. An equally plausible alternative five
   remains unresolved. Validate any changed rule on affected previously
   certified games before publishing additional components.
4. **Cross-source checks — existing licensed inputs only.** NBA game links use
   reviewed date/team identities. Player links require unique normalized full
   names within game/team plus agreement of every recorded counting statistic
   and source-minute precision. Unicode transliteration is explicit; no fuzzy
   aliases or guessed IDs are used. NBA-derived values compared with NBA boxes
   are dependent. Matching a shot on outcome is not independent outcome
   verification; separately unique time/player matches can expose conflicts.

## Failure classification

| Class | Evidence / disposition |
|---|---|
| Recoverable parsing defect | A recorded field or explicit description supplies an unambiguous interpretation; add a regression fixture |
| Recoverable ordering defect | Complete same-clock labels/native sequence support a unique causal order; retain a transformation audit |
| Source inconsistency | Current totals, identities or recorded outcomes disagree; preserve both records and require corroboration |
| Missing observations | Recorded FG/FT/TOV counts or periods are short; never create balancing events |
| Fundamental ambiguity | Multiple event, player or lineup interpretations remain feasible; keep noncertified/unresolved |

Diagnostics are cached under `data/processed/phase3/`. Failure totals must be
read with affected-game counts, season and current-input checks; findings are
not mutually exclusive. Actual recovery estimates are reported from pilots,
not extrapolated as guaranteed full-season success.

## Execution and preservation

Shot staging has season/source/input/method checkpoints and immutable normalized
Parquet artifacts. Relevant game, box, roster, PBP, NBA-snapshot and method inputs
invalidate a checkpoint; unrelated publication/report code does not. Publication
is additive and staged separately. Every original canonical row and frozen file
must survive. New certification is stricter than merely observing a row:
FGA/FGM/3PA/3PM and exact native links are checked, while coordinates can remain
missing. Spatial values are accepted only when the recorded native and
transformed pairs agree with the identified publisher convention and court bounds.

Physical recovery will select affected games after representative tests, use
an explicit method version and per-game checkpoints, and preserve certified
components. No expensive full historical backfill is scheduled. No new external
basketball data, paid API, defender assignments, research model or article is
part of this strategy.
