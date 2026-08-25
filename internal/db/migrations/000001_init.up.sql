CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE departments (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name       text NOT NULL UNIQUE,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE employees (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    department_id uuid REFERENCES departments (id) ON DELETE SET NULL,
    full_name     text NOT NULL,
    email         text NOT NULL,
    title         text,
    status        text NOT NULL DEFAULT 'active',
    hired_on      date,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT employees_status_check CHECK (status IN ('active', 'on_leave', 'exited'))
);

-- Case-insensitive uniqueness without requiring the citext extension.
CREATE UNIQUE INDEX employees_email_key ON employees (lower(email));
CREATE INDEX employees_department_id_idx ON employees (department_id);
