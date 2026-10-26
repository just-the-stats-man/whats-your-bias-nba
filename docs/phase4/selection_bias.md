# Missingness and selection diagnostics

Certification establishes consistency under stated gates, not representativeness.
The warehouse is a nonprobability collection of available source observations.
Season, provider completeness, event encoding and ability to establish unique
identities affect entry. Source-eligible canonical games are a useful observed
denominator, not a verified complete historical league schedule.

Generated reports compare selected and excluded canonical games by:

- [Season](selection_season.csv), including known-score/FGA counts, means and
  variances, free-throw activity and recorded positive-minute participation.
- [Team](selection_team.csv), including inclusion fractions and denominators.
- [Season/type/home-away](selection_type_home.csv), with separate observed team
  scoring/FGA/FTA means. Home and away records from one game are correlated.
- [Player participation](selection_player_participation.csv), restricted to
  recorded positive-minute observations, with explicit minute/sample counts.
- [LeBron-era coverage](lebron_research_coverage.csv), separating box games,
  certified shot games/attempts and physical cohorts.
- [Shot exclusions](shot_exclusion_reasons.csv) and
  [field missingness](research_missingness.csv).

The initial Phase 4 reports show especially strong season selection: 2021–22
has just 60 certified shot games out of 1,323 canonical games before the separate
missing-team-key recovery is evaluated. In contrast, the terminal-score fix
raises 2023–24 to 938 out of 1,318. The latter selected games average about
227.03 total points and 176.63 FGAs, compared with 227.93 points and 178.73 FGAs
among the remaining games. These descriptive differences are not causal effects
or a correction for unobserved selection. Later recovery reports supersede the
counts while preserving this diagnostic checkpoint.

Potentially affected questions include league shooting trends, career shot
profiles, era comparisons, pace/context comparisons, performance conditional on
specific lineups and player-impact studies. Conditioning on certified lineups
or location data further narrows an already selected game cohort. A valid
possession can lack a uniquely established five; excluding it changes the target
population again. FGA/FTA are recorded activity proxies here, not measured pace
or an inferred possession count.

Structural absence, source-missing values, failed validation, recorded zero,
explicit DNP, reconstructed classifications and provider model estimates are
kept distinct. Zero tracking *rows* means no acquired tracking observations;
it does not mean zero defender distance or zero dribbles. Historically unavailable
metrics must not be filled with modern means. NBA-native and canonical boxes
overlap and must not be combined as if independent games.

Future weighting would need a defined population, reliable inclusion covariates,
positivity and a defensible conditional selection assumption. Seasons or strata
with no usable observations violate practical positivity. Multiple imputation
would require a justified missingness model and uncertainty propagation, not a
blanket treatment of structural absence. Pattern-mixture or bounded sensitivity
analyses could examine departures from missing-at-random assumptions. None of
these adjustments or substantive outcome models is implemented in Phase 4.
