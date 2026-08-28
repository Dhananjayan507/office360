-- Organisations are the tenant root, so these are the only queries in the
-- codebase not scoped by organization_id. The /platform portal owns them; no
-- HTTP route reaches them yet.

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
INSERT INTO organizations (name, slug)
VALUES (sqlc.arg('name')::text, sqlc.arg('slug')::text)
RETURNING *;

-- name: UpdateOrganizationStatus :one
UPDATE organizations
SET status = sqlc.arg('status')::text,
    updated_at = now()
WHERE id = sqlc.arg('id')::uuid
RETURNING *;
