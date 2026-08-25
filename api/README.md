# api

API specifications — the contract, not the implementation.

The Go source lives at the repository root (`cmd/`, `internal/`). This directory
is for artefacts describing the HTTP surface:

| Expected | Purpose |
| --- | --- |
| `openapi.yaml` | The OpenAPI document for `/api/v1` |
| `examples/` | Request and response samples used in docs and tests |

Keeping the spec separate from the handlers means it can be reviewed, diffed and
published without dragging the server build along.

Empty for now. Every endpoint's shape is documented in the root `README.md`
under **API conventions** until the spec exists.
