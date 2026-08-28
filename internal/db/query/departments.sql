-- Every query is scoped by organization_id. A query without it is a
-- cross-tenant leak, so there are no unscoped variants to reach for by mistake.

-- name: ListDepartments :many
SELECT * FROM departments
WHERE organization_id = sqlc.arg('organization_id')::uuid
ORDER BY name;

-- name: GetDepartment :one
SELECT * FROM departments
WHERE organization_id = sqlc.arg('organization_id')::uuid
  AND id = sqlc.arg('id')::uuid;

-- name: CreateDepartment :one
INSERT INTO departments (organization_id, name)
VALUES (sqlc.arg('organization_id')::uuid, sqlc.arg('name')::text)
RETURNING *;

-- name: DeleteDepartment :execrows
DELETE FROM departments
WHERE organization_id = sqlc.arg('organization_id')::uuid
  AND id = sqlc.arg('id')::uuid;
