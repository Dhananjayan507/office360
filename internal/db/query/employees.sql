-- Every query is scoped by organization_id, writes included: an UPDATE or
-- DELETE matching on id alone would reach across tenants.

-- name: ListEmployees :many
SELECT * FROM employees
WHERE organization_id = sqlc.arg('organization_id')::uuid
  AND (sqlc.narg('department_id')::uuid IS NULL OR department_id = sqlc.narg('department_id')::uuid)
  AND (sqlc.narg('status')::employee_status IS NULL OR status = sqlc.narg('status')::employee_status)
ORDER BY full_name
LIMIT sqlc.arg('limit')::int OFFSET sqlc.arg('offset')::int;

-- name: CountEmployees :one
SELECT count(*) FROM employees
WHERE organization_id = sqlc.arg('organization_id')::uuid
  AND (sqlc.narg('department_id')::uuid IS NULL OR department_id = sqlc.narg('department_id')::uuid)
  AND (sqlc.narg('status')::employee_status IS NULL OR status = sqlc.narg('status')::employee_status);

-- name: GetEmployee :one
SELECT * FROM employees
WHERE organization_id = sqlc.arg('organization_id')::uuid
  AND id = sqlc.arg('id')::uuid;

-- name: CreateEmployee :one
INSERT INTO employees (
    organization_id, employee_code, department_id, designation_id, full_name,
    email, phone, status, employment_type, hired_on, created_by, updated_by
)
VALUES (
    sqlc.arg('organization_id')::uuid,
    sqlc.arg('employee_code')::text,
    sqlc.narg('department_id')::uuid,
    sqlc.narg('designation_id')::uuid,
    sqlc.arg('full_name')::text,
    sqlc.arg('email')::text,
    sqlc.narg('phone')::text,
    coalesce(sqlc.narg('status')::employee_status, 'probation'),
    coalesce(sqlc.narg('employment_type')::employment_type, 'full_time'),
    sqlc.narg('hired_on')::date,
    sqlc.narg('actor_id')::uuid,
    sqlc.narg('actor_id')::uuid
)
RETURNING *;

-- name: UpdateEmployee :one
UPDATE employees
SET department_id   = coalesce(sqlc.narg('department_id')::uuid, department_id),
    designation_id  = coalesce(sqlc.narg('designation_id')::uuid, designation_id),
    full_name       = coalesce(sqlc.narg('full_name')::text, full_name),
    email           = coalesce(sqlc.narg('email')::text, email),
    phone           = coalesce(sqlc.narg('phone')::text, phone),
    status          = coalesce(sqlc.narg('status')::employee_status, status),
    employment_type = coalesce(sqlc.narg('employment_type')::employment_type, employment_type),
    hired_on        = coalesce(sqlc.narg('hired_on')::date, hired_on),
    updated_at      = now(),
    updated_by      = coalesce(sqlc.narg('actor_id')::uuid, updated_by)
WHERE organization_id = sqlc.arg('organization_id')::uuid
  AND id = sqlc.arg('id')::uuid
RETURNING *;

-- name: DeleteEmployee :execrows
DELETE FROM employees
WHERE organization_id = sqlc.arg('organization_id')::uuid
  AND id = sqlc.arg('id')::uuid;
