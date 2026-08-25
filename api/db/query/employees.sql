-- name: ListEmployees :many
SELECT * FROM employees
WHERE (sqlc.narg('department_id')::uuid IS NULL OR department_id = sqlc.narg('department_id')::uuid)
  AND (sqlc.narg('status')::text IS NULL OR status = sqlc.narg('status')::text)
ORDER BY full_name
LIMIT sqlc.arg('limit')::int OFFSET sqlc.arg('offset')::int;

-- name: CountEmployees :one
SELECT count(*) FROM employees
WHERE (sqlc.narg('department_id')::uuid IS NULL OR department_id = sqlc.narg('department_id')::uuid)
  AND (sqlc.narg('status')::text IS NULL OR status = sqlc.narg('status')::text);

-- name: GetEmployee :one
SELECT * FROM employees
WHERE id = sqlc.arg('id')::uuid;

-- name: CreateEmployee :one
INSERT INTO employees (department_id, full_name, email, title, status, hired_on)
VALUES (
    sqlc.narg('department_id')::uuid,
    sqlc.arg('full_name')::text,
    sqlc.arg('email')::text,
    sqlc.narg('title')::text,
    coalesce(sqlc.narg('status')::text, 'active'),
    sqlc.narg('hired_on')::date
)
RETURNING *;

-- name: UpdateEmployee :one
UPDATE employees
SET department_id = coalesce(sqlc.narg('department_id')::uuid, department_id),
    full_name     = coalesce(sqlc.narg('full_name')::text, full_name),
    email         = coalesce(sqlc.narg('email')::text, email),
    title         = coalesce(sqlc.narg('title')::text, title),
    status        = coalesce(sqlc.narg('status')::text, status),
    hired_on      = coalesce(sqlc.narg('hired_on')::date, hired_on),
    updated_at    = now()
WHERE id = sqlc.arg('id')::uuid
RETURNING *;

-- name: DeleteEmployee :execrows
DELETE FROM employees
WHERE id = sqlc.arg('id')::uuid;
