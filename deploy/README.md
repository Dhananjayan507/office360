# deploy

Deployment configuration, kept out of the application tree.

| Expected | Day | Purpose |
| --- | --- | --- |
| `Caddyfile` | 14 | Reverse proxy and automatic HTTPS |
| `Dockerfile` | 14 | Multi-stage build producing the single binary |
| `compose.prod.yml` | 14 | Production compose, distinct from the local dev stack |

Local development does not use anything in here — that is `docker-compose.yml`
at the repo root, which runs Postgres only.

Nothing in this directory may contain real credentials. Secrets come from the
environment at deploy time; `.env` is gitignored and must stay that way.

Empty until Day 14.
