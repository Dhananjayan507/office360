# internal/platform

Cross-cutting concerns every module depends on but none of them owns.

| Package | Day | Holds |
| --- | --- | --- |
| `auth/` | 3 | Argon2id hashing, JWT issue/verify, login, refresh, logout |
| `authz/` | 4 | `Can(role, module, action)` — the single place a permission is decided |
| `tenant/` | 4 | Middleware putting `organization_id` in request context; fails closed |
| `audit/` | 4 | `logAudit()` writing actor, action, entity, before/after in the caller's transaction |

Nothing here may import `internal/modules` — the dependency runs one way only,
or the permission rules end up depending on the features they are meant to gate.

Empty until Day 3. The directory exists now so no folder needs creating later.
