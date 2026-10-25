# SportsDataverse historical execution

The pinned archive supplies schedules and both box families from 1993–94,
and PBP from 2001–02. Files are cached once and raw SHA-256 manifests are retained.

```sh
Rscript scripts/cache_sdv_history.R
Rscript scripts/ingest_sdv_history_parallel.R 1994 1995 1996 1997 1998 1999 2000 2001 2002 2003 2004 2005 2006 2007 2008 2009 2010 2011 2012 2013 2014 2015
Rscript scripts/recover_sdv_nba_boxes.R 1994 1995 1996 1997 1998 1999 2000 2001 2002 2003 2004 2005 2006 2007 2008 2009 2010 2011 2012 2013 2014 2015
Rscript scripts/reconstruct_sdv_history.R
```

The historical adapter is separate from the four files defining the verified
modern reconstruction fingerprint. Existing player names are preserved.
Valid boxes are admitted independently of PBP; invalid/missing event families
remain flagged and are excluded from physical reconstruction. Derived snapshots
have their own hashes and dependency edges to all relevant immutable raw inputs.

Some older ESPN records duplicate the reported turnover aggregate into a
component and add it twice. The adapter retains the recorded aggregate as the
team-inclusive total and derives player turnovers only from complete recorded
player rows when the aggregate is at least that sum. Raw values remain untouched;
every transformation is logged. Subsequent PBP and NBA comparisons can reject
the interpretation for a game. No difference is filled with a guessed value.

Explicit shot descriptions and annotations classify attempts. An unclassified
miss can also receive a **reconstructed** value if complete FGA/FGM/3PM counts
leave a unique remaining assignment: all remaining attempts must be twos, or all
must be threes. A mixed assignment stays missing. This never creates coordinates,
new attempts, scoring events, substitutions or defensive assignments. Classified
shot rows remain distinguishable from observations in `observation_type` and
normalization exceptions.

Physical reconstruction uses the original possession, minute, membership and
reconciliation gates. Only games with admitted event records enter workers.
Workers have isolated DuckDB files, fingerprinted frozen inputs and per-game
checkpoints. Completed/partial workers can resume. Native SQL publication avoids
large R transfers and timestamp precision loss, and publishes only the selected
game IDs in a transaction after integrity checks. An unchanged published
snapshot is reused; changed inputs require a different output directory.
The snapshot signature covers full selected game, box, event and check rows,
reference turnover totals and provider identities. A minutes-only correction
therefore cannot reuse stale physical results. Older snapshots with saved
input tasks can upgrade their signature only when the physical method and all
selected frozen inputs match current facts; finished workers are then reused.
Unrelated games do not invalidate a scoped snapshot.

All 22 historical source partitions were integrated on 2026-10-25. Parallel
ingestion uses isolated staging databases and publishes each season after
integrity checks. It skips published signatures and reuses finished staging
databases after interruption. The 1998–99 and 1999–00 archives need a narrowly
scoped calendar adapter: recorded dates identify mixed season labels, and the
1999–00 archive contains 500 prior-season schedule copies. All 500 also occur
in the correct archive. Raw copies remain; only date-qualified season records
are promoted. This correction does not invalidate the other 20 partitions.

Whole NBA boxes may replace a **failed** historical ESPN box family when exact
full names, game/date and reviewed team mappings are unique and every available
ESPN counting statistic agrees. Normalization of names only ignores case and
repeated whitespace; there is no fuzzy matching. Missing ESPN statistics are
not filled individually. Complete NBA player/team boxes must pass the existing
box gate, source-minute precision checks, and scoring identities. An explicit
NBA DNP/inactive comment is required to interpret missing nonplaying minutes;
the ESPN `active` field alone is insufficient. A DNP cannot appear as a PBP
actor. Cross-game identity conflicts are rejected and mappings are retained in
`sdv_nba_player_links`. Existing player names stay unchanged.

Recovered boxes keep the NBA provider and all raw dependencies. Their agreement
with NBA reference totals is **dependent**; it cannot certify independent
reconciliation. PBP remains ESPN evidence and must pass its own gate. Recovery
skips completed games and batches manifest publication; it does not rerun the
normalization/classification snapshots. Reports must use current statuses,
rather than counting preserved earlier failed exceptions as current failures.

Use the season/status tables and resulting completeness reports to assess
coverage. Cached source files alone are not evidence of analytically complete
seasons. The existing historical NBA observation layer remains available for
earlier years and cross-provider checks. A refreshed Git tree comparison found
no changes to the pinned 2015–16 through 2025–26 source files; only the active
2026–27 partition changed. See `sdv_latest_archive_audit.csv`.
