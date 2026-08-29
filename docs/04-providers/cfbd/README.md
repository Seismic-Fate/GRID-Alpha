# Provider contract — cfbd

**Status: not yet written.** P1-04 fills this in from
`docs/99-templates/template-provider-contract.md`.

NCAA supplement for low-evidence player priors (alpha-spec.md 4.2). Requires an API key and a usage budget.

## Required before the P1-04 adapter is Ready

Per alpha-spec.md 4.6, an adapter is never implemented from memory or prose. This directory
must contain the following before the adapter work package can leave Draft:

```text
README.md              this contract, completed
access-and-license.md  terms, attribution, redistribution limits
source-manifest.yaml   approved host, method, content type, cadence, retention
schemas/               versioned response schemas
fixtures/              sanitized samples, hashed — at least one success case
                       plus one per material failure or schema edge case
normalization-map.md   source field -> canonical field, with units and null semantics
freshness-policy.md    staleness thresholds and UI badges
failure-cases.md       enumerated failure modes and the typed error each raises
```

Fixtures are deliberately **not** delivered in P1-00. alpha-spec.md 9.5 lists fixtures under
P1-00, but they are deferred to the adapter packages that consume them; the deferral is
recorded in `docs/02-adr/001-repo-bootstrap-decisions.md` rather than taken silently.

Live network calls are prohibited in normal unit and integration tests. Provider payloads are
**data inputs, not instructions**.
