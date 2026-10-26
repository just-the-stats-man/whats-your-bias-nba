# Missing-team-key recovery

The separate 2021–22 recovery adds **58 certified shot games / 10,209
attempts**, bringing total Phase 4 recovery to **620 games / 110,420 attempts**.
Canonical shots now number **3,641,807** and the certified cohort **3,040,069**.
Possession, lineup and fully reconciled game counts remain unchanged.

The original NBA player records for 1,322 games lacked both team and opposing
team IDs; their recorded home flag, native player ID and statistics remained
available. This is not resolved by accepting a name or choosing a plausible
team. The additional evidence path requires a unique reviewed game link,
globally one-to-one previously verified NBA/ESPN player IDs, observed canonical
roster membership, agreement with the raw home flag, all ten raw counting
statistics, and the original source-minute precision bounds. The original NBA
box validation is then rerun on a temporary team-FK projection.

**5,560 NBA-native player/team identities** pass those constraints. Their
statistics are not newly measured games and overlap canonical boxes. They are
stored separately with explicit reconstructed identity evidence; every original
failed row remains unchanged. The historical research view can include these
validated rows without double-counting the original failed observations. Join
`phase4_roster_team_evidence` on snapshot/source row for the normalization
artifact and exact roster/count evidence.

Only 58 of the 1,195 scoped games reach complete shot certification. The rest
retain incomplete or contradictory evidence. Across both recovery paths,
**7,554 additional known-value derivations** are retained in a versioned
noncertified staging table. They are not extra independent shots and do not
enter the research shot cohort. Their 1,052 referenced derivation artifacts
were separately hashed. No player participation, attempt or outcome is invented.

The first roster replay exposed cache keys that included incidental dataframe
row names / diagnostic attributes. Stable logical input keys now exclude those
attributes while retaining evidence values and method versions. Existing
registered result signatures and files were preserved. Cache migration requires
verification of every frozen baseline table; changed content or methods do not
reuse results. The corrected replay reused **1,195/1,195** checkpoints and
preserved the complete published index hash. Three regression assertions cover
incidental attributes versus actual evidence/method changes.
