-- Reverses 000002.
--
-- Development-only in practice. Collapsing a tenanted database back to a
-- single-tenant schema cannot succeed once a second organisation exists: two
-- organisations may both hold a "Finance" department or the same employee email,
-- and the global unique constraints restored below would reject them. Roll back
-- only on a database that still has one organisation.

DROP INDEX employees_org_department_idx;
CREATE INDEX employees_department_id_idx ON employees (department_id);

DROP INDEX employees_org_email_key;
CREATE UNIQUE INDEX employees_email_key ON employees (lower(email));

ALTER TABLE employees DROP CONSTRAINT employees_department_fkey;
ALTER TABLE employees ADD CONSTRAINT employees_department_id_fkey
    FOREIGN KEY (department_id) REFERENCES departments (id) ON DELETE SET NULL;

ALTER TABLE employees DROP COLUMN organization_id;

ALTER TABLE departments DROP CONSTRAINT departments_org_id_key;
DROP INDEX departments_org_name_key;
ALTER TABLE departments ADD CONSTRAINT departments_name_key UNIQUE (name);

ALTER TABLE departments DROP COLUMN organization_id;

DROP TABLE organizations;
