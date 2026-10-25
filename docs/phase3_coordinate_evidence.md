# Coordinate evidence receipt

The existing SportsDataverse archive records both source-native and transformed
coordinate pairs. We validate the published transform, without inferring a shot
type from distance or replacing a missing location.

Publisher implementation: [`helper_espn_nba_pbp`](https://github.com/sportsdataverse/hoopR/blob/be93b9eece683efffdcada47126349d75498b750/R/espn_nba_data.R),
file commit `be93b9eece683efffdcada47126349d75498b750` (2026-10-21),
retrieved 2026-10-25. SHA-256 of the complete reviewed source file:
`789f6d392ee22d6a336ab3dedf7996d0d80deb828f8544e72263abebd20f58d5`.
Local review copies are in `data/processed/phase3/hoopr_espn_nba_data*.R`.
The file is covered by the publisher's [MIT license](https://github.com/sportsdataverse/hoopR/blob/be93b9eece683efffdcada47126349d75498b750/LICENSE.md),
copyright 2020 hoopR authors. This is a code/documentation receipt, not a new
basketball data license or an additional observation source.

For a home-team attempt, transformed x = 41.75 − native y and transformed
y = 25 − native x; away values have opposite signs. Units are feet, centered
on the court, with the home team attacking positive x. Both native components,
canonical home/away identity, numerical agreement within 1e-6 and court bounds
must be available. Implausible sentinels fail validation. An unidentified frame
keeps the standardized pair missing and retains both published pairs as evidence.
The convention identifies the publisher's frame; it does not certify optical
measurement accuracy. Missing coordinates never remove an observed attempt.

The free-throw coordinate special case in the publisher code is irrelevant to
the field-goal table, which explicitly excludes free throws.
