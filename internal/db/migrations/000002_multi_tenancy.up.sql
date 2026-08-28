-- Day 2: multi-tenancy.
--
-- Isolation is enforced by the schema, not by remembering to add a WHERE clause:
--
--   * organization_id is NOT NULL on every business table, so no row can sit
--     outside a tenant.
--   * Unique constraints are scoped to the organisation, so two organisations
--     may each have a "Finance" department without colliding.
--   * Foreign keys between business tables are COMPOSITE and carry
--     organization_id, so a row can never reference another tenant's row even if
--     the service layer forgets to check.
--
-- organization_id is the first column of every table created from here on.
-- On the two tables that predate this migration it is appended instead, because
-- Postgres cannot reposition a column without rewriting the table.

CREATE TABLE organizations (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name       text NOT NULL,
    slug       text NOT NULL,
    status     text NOT NULL DEFAULT 'active',
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT organizations_status_check CHECK (status IN ('active', 'suspended', 'closed'))
);

-- Slugs address an organisation in URLs and at login, so they collide
-- case-insensitively.
CREATE UNIQUE INDEX organizations_slug_key ON organizations (lower(slug));

-- The organisation that existing rows are adopted into. The id is fixed rather
-- than generated so a rebuilt database keeps the same value and local tooling
-- has something stable to point at.
INSERT INTO organizations (id, name, slug)
VALUES ('00000000-0000-0000-0000-000000000001', 'Default Organisation', 'default');

-- --- departments -------------------------------------------------------------

ALTER TABLE departments
    ADD COLUMN organization_id uuid REFERENCES organizations (id) ON DELETE CASCADE;

UPDATE departments
SET organization_id = '00000000-0000-0000-0000-000000000001'
WHERE organization_id IS NULL;

ALTER TABLE departments ALTER COLUMN organization_id SET NOT NULL;

-- A department name is unique within an organisation, not across the platform.
ALTER TABLE departments DROP CONSTRAINT departments_name_key;
CREATE UNIQUE INDEX departments_org_name_key ON departments (organization_id, lower(name));

-- The target the composite foreign key below points at.
ALTER TABLE departments ADD CONSTRAINT departments_org_id_key UNIQUE (organization_id, id);

-- --- employees ---------------------------------------------------------------

ALTER TABLE employees
    ADD COLUMN organization_id uuid REFERENCES organizations (id) ON DELETE CASCADE;

UPDATE employees
SET organization_id = '00000000-0000-0000-0000-000000000001'
WHERE organization_id IS NULL;

ALTER TABLE employees ALTER COLUMN organization_id SET NOT NULL;

ALTER TABLE employees DROP CONSTRAINT employees_department_id_fkey;

-- Composite, so an employee can only be filed under a department in its OWN
-- organisation. A plain (department_id) reference would happily accept another
-- tenant's department id.
--
-- The column list on SET NULL is required and needs Postgres 15 or newer: the
-- bare form would try to null organization_id as well, which is NOT NULL.
ALTER TABLE employees ADD CONSTRAINT employees_department_fkey
    FOREIGN KEY (organization_id, department_id)
    REFERENCES departments (organization_id, id)
    ON DELETE SET NULL (department_id);

DROP INDEX employees_email_key;
CREATE UNIQUE INDEX employees_org_email_key ON employees (organization_id, lower(email));

-- Replaces the single-column index: every query is scoped by organisation, so
-- that has to lead, and the composite also serves the foreign key above.
DROP INDEX employees_department_id_idx;
CREATE INDEX employees_org_department_idx ON employees (organization_id, department_id);
