# Season completeness

Generated in UTC: 2026-10-24 17:14:55 UTC
Reconstruction method: pl-v1-74d5a845d796

All counts refer to completed NBA franchise games, including play-ins and Cup finals.
A completed backfill attempt is not a claim that every source game passes analytical validation.
Reference counts come from a separate NBA-derived feed; neither archive is assumed complete.
Reference-dependent team boxes are identified separately; comparisons to their own source are not independent.
Fully reconciled requires both reconstructions and all game-level checks to agree independently.
Raw archives are preserved locally. Missing, quarantined and unresolved games remain explicit.

|season  | source_games| canonical_games| quarantined_games| reference_matched_games| reference_agree_games| possessions_reconciled| lineups_reconciled| fully_reconciled_games|
|:-------|------------:|---------------:|-----------------:|-----------------------:|---------------------:|----------------------:|------------------:|----------------------:|
|2015-16 |         1316|            1300|                16|                    1300|                  1296|                    370|                477|                    357|
|2016-17 |         1309|            1296|                13|                    1296|                  1290|                    728|               1007|                    689|
|2017-18 |         1312|            1304|                 8|                    1304|                  1297|                    712|                692|                    472|
|2018-19 |         1312|            1270|                42|                    1270|                  1270|                    852|                698|                    530|
|2019-20 |         1143|            1133|                10|                    1133|                  1131|                    881|                691|                    588|
|2020-21 |         1171|            1161|                10|                    1161|                  1155|                    918|               1005|                    858|
|2021-22 |         1323|            1323|                 0|                    1323|                  1323|                   1044|               1155|                    990|
|2022-23 |         1320|            1320|                 0|                    1320|                  1318|                   1082|               1152|                    986|
|2023-24 |         1319|            1318|                 1|                    1318|                  1315|                   1072|               1169|                   1004|
|2024-25 |         1321|            1321|                 0|                    1315|                  1314|                   1036|               1094|                    902|
|2025-26 |         1322|            1305|                17|                    1305|                  1298|                    380|                429|                    358|
|2026-27 |           16|              16|                 0|                      16|                    16|                      4|                  3|                      3|

See season_completeness.csv for all denominators, game_validation_status.csv for each source game,
reference_only_games.csv and source_only_games.csv for unmatched records, and exception_summary.csv.
reference_dependent_boxes.csv identifies canonical boxes compared back to the same provider.
A reconciled reconstruction passed event totals, score conservation and control/clock constraints.
Lineups additionally require exactly five unique players, complete period coverage and player-minute bounds.
This does not certify unobserved ground truth or assign any defender. Both providers may share upstream errors.
