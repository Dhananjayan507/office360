-- name: ListDepartments :many
SELECT * FROM departments
ORDER BY name;

-- name: GetDepartment :one
SELECT * FROM departments
WHERE id = $1;

-- name: CreateDepartment :one
INSERT INTO departments (name)
VALUES ($1)
RETURNING *;

-- name: DeleteDepartment :execrows
DELETE FROM departments
WHERE id = $1;
