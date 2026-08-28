-- Organisations are the tenant root, so these are the only queries in the
-- codebase not scoped by organization_id.

-- name: ListOrganizations :many
SELECT * FROM organizations
ORDER BY name;

-- name: GetOrganization :one
SELECT * FROM organizations
WHERE id = sqlc.arg('id')::uuid;

-- name: GetOrganizationBySlug :one
SELECT * FROM organizations
WHERE lower(slug) = lower(sqlc.arg('slug')::text);

-- name: CreateOrganization :one
INSERT INTO organizations (name, slug, legal_name, gstin, pan, state_code, created_by)
VALUES (
    sqlc.arg('name')::text,
    sqlc.arg('slug')::text,
    sqlc.narg('legal_name')::text,
    sqlc.narg('gstin')::text,
    sqlc.narg('pan')::text,
    sqlc.narg('state_code')::text,
    sqlc.narg('created_by')::uuid
)
RETURNING *;

-- name: UpdateOrganizationStatus :one
UPDATE organizations
SET status = sqlc.arg('status')::organization_status,
    updated_at = now(),
    updated_by = sqlc.narg('updated_by')::uuid
WHERE id = sqlc.arg('id')::uuid
RETURNING *;
