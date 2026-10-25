# Missingness and research capability

Historical ingestion is additive. It does not weaken canonical game, possession
or lineup gates. Source values remain immutable; standardized values can be
null even when a source encodes zero. IDs retain provider namespaces. Dates and
the NBA season suffix jointly resolve centuries. The NBA observation adapter
uses native IDs. Whole-box recovery separately requires unique exact full
names within a mapped game/team and agreement of all available ESPN counts;
it retains every mapping and rejects ambiguity. No fuzzy identity matching is
used. Provider tracking names remain unmapped labels.

| Status | Meaning |
|---|---|
| observed | A recorded measurement is available; this label alone does not mean a complete box or season. |
| reconstructed | Deterministic derivation from recorded evidence, with the stated checks passed. |
| estimated | Statistical model output; never an observed historical measurement. |
| not_collected | Measurement was not recorded in this era. |
| source_missing | Expected measurement is absent, ambiguous or encoded as an unavailable placeholder. |
| failed_validation | Evidence contradicts required identities or identifiers. |
| not_licensed | Relevant data exist but current access rights are insufficient. |
| not_applicable | Measurement does not apply, such as NBA three-pointers before their introduction. |

Zero must survive only when supported by the recorded field and context. For example, an early team's nonzero makes alongside zero attempts demonstrate missing attempts, not perfect measurement of zero attempts. Before a category's recording era, even a zero has no observed interpretation. Historical player minutes of zero with positive scoring evidence are not zero-minute appearances. Unknown turnover components do not become zero.

## Supported questions

| Research question | Evidence classification and limitation |
|---|---|
| Individual scoring / shooting efficiency | Recorded boxes; efficiency only with known valid attempts and complete denominators. Sparse game sums are partial coverage. |
| Shot selection | Observed event descriptions/coordinates where available; coordinate systems stay provider-specific. Unclassified shot value remains missing. |
| Shot quality | Estimable with explicit covariates, training population and uncertainty; no models added in this phase. |
| Player impact / opponent adjustment | Estimable with assumptions about selection, confounding, coverage and opponent strength; causal effects are not directly observed. |
| Five-player performance / defensive lineup impact | Reconstructable only in games passing substitution, five-player membership and minute checks. Shared court time does not assign defensive responsibility. |
| Player matchups | Unavailable without an explicit matchup source and its definition. Actor IDs in PBP do not identify assigned defenders. |
| Nearest defender / defender distance | A licensed 2015–16 provider feature release supplies estimated release distances and nearest-player labels, with unknown uncertainty. No optical reproduction or assignment is asserted. See tracking_assessment.md. |
| Help defense / switches / off-ball movement / screen navigation | Currently unavailable as observations; require licensed trajectories or documented hand-charting. Not recoverable from ordinary PBP. |

The concepts **on court**, **assigned defender**, **nearest defender at release**
and **responsible defender** require different evidence. Canonical data support
validated on-court membership. A separate feature table retains provider
nearest-player estimates. It never converts proximity, steals, blocks, positions
or roster membership into assignment or responsibility.

## Separate future modeling contract

No historical values are imputed. A future modeling layer must key each result by observed entity, metric, model version, training snapshot, imputation draw, missingness status and assumption set. Store estimates and intervals separately from observed values; never update observational tables. Produce missingness-by-era/team/source diagnostics first. Distinguish structural noncollection from MAR/MNAR hypotheses; neither is identified by missingness alone. Multiple imputation must preserve draw-to-draw uncertainty and report pooled within/between-imputation variance. Sensitivity analyses must vary missingness assumptions and include complete-case/observed-only comparisons. Do not impute trajectories or defender distances that were never recorded and describe them as recovered measurements.
