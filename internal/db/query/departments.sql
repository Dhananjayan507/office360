-- Every query is scoped by organization_id. There are no unscoped variants to
-- reach for by mistake.

-- name: ListDepartments :many
SELECT * FROM departments
WHERE organization_id = sqlc.arg('organization_id')::uuid
ORDER BY name;

-- name: GetDepartment :one
SELECT * FROM departments
WHERE organization_id = sqlc.arg('organization_id')::uuid
  AND id = sqlc.arg('id')::uuid;

-- name: CreateDepartment :one
INSERT INTO departments (organization_id, code, name, parent_id, created_by, updated_by)
VALUES (
    sqlc.arg('organization_id')::uuid,
    sqlc.narg('code')::text,
    sqlc.arg('name')::text,
    sqlc.narg('parent_id')::uuid,
    sqlc.narg('actor_id')::uuid,
    sqlc.narg('actor_id')::uuid
)
RETURNING *;

-- name: DeleteDepartment :execrows
DELETE FROM departments
WHERE organization_id = sqlc.arg('organization_id')::uuid
  AND id = sqlc.arg('id')::uuid;
