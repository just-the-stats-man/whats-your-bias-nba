# Terminal-score recovery milestone

The initial scoped recovery adds **100,211 canonical and certified attempts
across 562 games**. Canonical shots rise from 3,531,387 to 3,631,598; certified
shots rise from 2,929,649 to 3,029,860. All possession and lineup counts remain
unchanged. The original certified cohort and every original source/table row
are preserved, with superseded noncertified candidate/check rows archived.

For 2023–24, 180 games / 32,198 attempts are recovered: 165,682 certified
attempts against 233,601 canonical box FGAs, or 70.93%, compared with 57.14%
before this milestone. See [season comparisons](shot_coverage_before_after.csv).

The legacy NBA check treated the maximum native event number as the final
score. Late-added corrections can have larger numbers than the observed
zero-clock `Game End` event while referring to earlier play. We use a unique
explicit terminal score pair, require the maximum observed period and exact
zero clock, and compare it with both NBA game and team totals. Competing
terminal pairs remain unresolved. The eight original NBA shooting checks,
full player identity/count/minute gates, one-to-one event matching and all
canonical FGA/FGM/3PA/3PM gates still apply.

This is an additional versioned evidence path; legacy failed checks remain
stored. No raw event is reordered and no score is inferred from a matching box.
Every new artifact carries native NBA terminal-event/source-row pointers.
Publication passed **219 integrity/preservation checks**, including preservation
of all Phase 3 certified shots. Repeating publication added zero rows. An
unchanged 822-game resume had 822 checkpoint hits and preserved the complete
index SHA-256. The upper bound was 146,595 attempts; candidates that still fail
identity, value or event gates remain noncertified.

The 2021–22 pilot recovered no attempts: 1,322 NBA games' player records lack
resolved team identities and remain failed under the existing gates. A separate
diagnostic now examines whether recorded home-side information and already
verified cross-provider roster identities can supply those missing keys without
weakening identity validation. No such recovery is counted here.
