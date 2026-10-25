# Shot recovery milestone

Verified against Phase 2 commit `c391b10`, with all 299 original assertions and
all 85 original production integrity checks preserved. The initial augmented
production verification passed 135 integrity/preservation checks.

The main extraction defect was a required `points_attempted` annotation that
is absent or sparse in many archive schemas. Recorded FG flags and outcomes
were present. Some misses also lack an explicit two/three label; those require
an existing uniquely linked NBA observation or a unique shooting-count solution.
Missing events, unmatched identities, inconsistent source contexts and DNP
contradictions remain unresolved.

The additive publication recovers **1,203,614 canonical attempts**, raising the
preserved canonical table from 2,327,773 to 3,531,387 rows. Its newly revalidated
subset contains **2,929,649** attempts across the cached seasons. These are
different counts: preserved older canonical rows can remain uncertified under
the new checks. Three games with 14 observed shooter/DNP contradictions are
withheld as whole games; their 457 candidates remain noncertified.

For 2023–24, canonical rows rise from **1,430 to 133,661**; **133,484** pass the
new certification gates, or **57.14%** of 233,601 canonical box FGAs. There are
233,588 recorded canonical-game FG candidates, so the aggregate observed count
is 13 below the boxes. Opposing game/team discrepancies cannot cancel each
other for certification. The remaining candidates retain their source pointers
and reasons; none is filled to a target count.

See [season counts](shot_completeness.csv), [metric-level discrepancies](shot_discrepancies.csv),
and [candidate exception categories](shot_exceptions.csv). Fractions use admitted
canonical boxes, not a claim of complete league schedules. Whole-game
certification requires both teams' FGA/FGM/3PA/3PM, verified actors, no duplicate
events and consistent source context. Missing locations do not reject attempts.
Only the independently identified publisher coordinate frame supplies standard
coordinates; see the [evidence receipt](../phase3_coordinate_evidence.md).

NBA-derived shot values and box-constrained values carry reconstructed status.
Agreement with the constraint used to derive a value is a consistency check,
not independent validation. Matching on outcome does not independently verify
that outcome. Separately unique event matches can expose disagreements.
No tracking measurements or defender assignments were created.
