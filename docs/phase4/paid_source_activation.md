# Optional sources: activation and boundaries

**No paid purchase, paid trial, authenticated API call or live provider
integration was performed during this implementation.** Tests use clearly
synthetic mocked payloads. A configured credential never authorizes spending.

## DunkAPI

The optional adapter follows the provider's public
[REST/get_plays schema](https://dunkapi.com/docs/get-plays). It accepts one
explicit game, preserves every raw JSON response by SHA-256, uses a sorted
request/parameter cache key, validates schemas/counts, and retains source rows
separately from canonical observations. Native sequence is not assumed to be
the original ESPN event ID. Upstream independence remains unverified/false.
Expected points and win probability are estimates, separate from observations.
Coordinates remain raw and unverified against a canonical frame. FT and FG
records are distinguished explicitly; duplicate native game/sequence records
are retained and fail validation. Nothing is promoted automatically.

After explicit user approval for a specific request/credit budget:

1. Create/configure an account directly with the provider and inspect its
   accepted terms. Do not activate a paid trial or wallet without approval.
2. Configure `DUNKAPI_API_KEY` locally as an environment variable. Never paste
   it into chat, URLs, command arguments, reports, or Git.
3. Copy `config/dunkapi_approval.example.json` to a private location outside Git,
   set its separately approved ID, endpoint list, maximum credits, UTC expiry,
   accepted-terms acknowledgement and approval flag. Set the local environment
   variable `DUNKAPI_APPROVAL_FILE` to that private path. The committed example
   is deliberately disabled and expired; editing it does not supply approval.
4. Run a single scoped request, for example
   `Rscript scripts/dunkapi.R 401585601`. Use the returned `next_offset` for an
   explicitly budgeted next page, e.g. `Rscript scripts/dunkapi.R 401585601 1000`.
   A limit of 1000 is shown in the provider's coverage example; actual server
   limits and completeness must still be verified in the pilot.

Live requests reserve credits before transport. Errors are counted against
the local safety cap; refunds are not assumed. There are no automatic retries
or unbounded pagination. Requests are spaced at least 6.1 seconds apart,
matching the stricter advertised ten-per-minute low-balance limit. An approval
ledger and exclusive request lock prevent concurrent budget races. Error
bodies and credential-bearing responses are not logged or cached. Cache hits
verify hashes and require no new request or credential. To inspect a later
upstream revision, use a separately designated cache directory and explicit
approval; immutable older snapshots are retained.

The initial proposed 20-game, 500-credit cap fits the advertised free allowance
only while that allowance is actually available. A key can also access paid
wallet credits, so **do not assume a call is free because an account has a free
tier**. Account billing must be reviewed before approving calls. Tests cover
cap exhaustion, no-approval/no-key behavior, failed calls, corruption, duplicate
records, FT classes, missing coordinates and repeat ingestion.

`supplementary_snapshots` retains request/schema/access receipts;
`dunkapi_play_observations` retains immutable response-row keys and reported
fields. Full raw files live under ignored `data/raw/authorized/dunkapi/`.
Live schema validity and actual marginal coverage are still unverified.

## Tracking / BBall Index / other authorized manual exports

No private export schema is invented. After obtaining a lawful manual CSV and
written retention/use permissions, call `ingest_authorized_export()` with the
provider, actual observational unit, explicit native key columns and permission
receipt. Retention approval is mandatory; modeling, derived publication and
raw redistribution permissions remain separate flags. Keep the written grant
and its hash in the private receipt. A sample-shaped aggregate/filter record
cannot silently be relabeled as an individual shot.

Raw rows, empty strings, recorded zero labels, bucket text and duplicates are
preserved in `supplementary_export_records`. Imports stay unvalidated and do
not enter certified or research cohorts automatically. An export-specific
validated schema and identifier mapping must be reviewed after the actual
header and dictionary are available. Public website membership does not grant
an API or bulk-download license. No login, paywall or restriction is bypassed.

Provider comparison, current costs and the rights questions to resolve are in
[the assessment](provider_assessment.md). No provider message has been sent.
