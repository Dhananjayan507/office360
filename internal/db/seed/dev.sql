-- Development seed. Idempotent: safe to run repeatedly.
--
-- Run with ./make.ps1 seed. This is NOT a migration and never runs in
-- production — migrations own the schema, this owns a handful of rows to look
-- at while building.
--
-- The ids below are fixed rather than generated, so .env.example can name the
-- organisation and a rebuilt database keeps the same value. They are still
-- valid v7 shapes (version nibble 7, variant nibble 8) but obviously synthetic,
-- which is the point: a real record never looks like this.

INSERT INTO organizations (id, name, slug, legal_name, gstin, pan, state_code, city, country)
VALUES (
    '00000000-0000-7000-8000-000000000001',
    'Demo Organisation',
    'demo',
    'Demo Organisation Private Limited',
    '33AAAAA0000A1Z5',
    'AAAAA0000A',
    '33',
    'Chennai',
    'IN'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO departments (id, organization_id, code, name)
VALUES
    ('00000000-0000-7000-8000-000000000010', '00000000-0000-7000-8000-000000000001', 'ENG', 'Engineering'),
    ('00000000-0000-7000-8000-000000000011', '00000000-0000-7000-8000-000000000001', 'FIN', 'Finance'),
    ('00000000-0000-7000-8000-000000000012', '00000000-0000-7000-8000-000000000001', 'OPS', 'Operations')
ON CONFLICT (id) DO NOTHING;

INSERT INTO designations (id, organization_id, name, grade, level)
VALUES
    ('00000000-0000-7000-8000-000000000020', '00000000-0000-7000-8000-000000000001', 'Software Engineer', 'E2', 2),
    ('00000000-0000-7000-8000-000000000021', '00000000-0000-7000-8000-000000000001', 'Accountant', 'F2', 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO employees (
    id, organization_id, employee_code, department_id, designation_id,
    full_name, email, status, employment_type, hired_on
)
VALUES
    ('00000000-0000-7000-8000-000000000030', '00000000-0000-7000-8000-000000000001', 'EMP-001',
     '00000000-0000-7000-8000-000000000010', '00000000-0000-7000-8000-000000000020',
     'Ada Lovelace', 'ada@office360.dev', 'active', 'full_time', DATE '2026-04-01'),
    ('00000000-0000-7000-8000-000000000031', '00000000-0000-7000-8000-000000000001', 'EMP-002',
     '00000000-0000-7000-8000-000000000010', '00000000-0000-7000-8000-000000000020',
     'Grace Hopper', 'grace@office360.dev', 'probation', 'full_time', DATE '2026-07-15'),
    ('00000000-0000-7000-8000-000000000032', '00000000-0000-7000-8000-000000000001', 'EMP-003',
     '00000000-0000-7000-8000-000000000011', '00000000-0000-7000-8000-000000000021',
     'Katherine Johnson', 'katherine@office360.dev', 'active', 'contract', DATE '2026-05-20')
ON CONFLICT (id) DO NOTHING;

-- A second organisation, so cross-tenant behaviour can be exercised by hand:
-- point X-Organization-Id at this one and the rows above must vanish.
INSERT INTO organizations (id, name, slug, state_code, country)
VALUES ('00000000-0000-7000-8000-000000000002', 'Acme Test Org', 'acme', '29', 'IN')
ON CONFLICT (id) DO NOTHING;

INSERT INTO departments (id, organization_id, code, name)
VALUES ('00000000-0000-7000-8000-000000000013', '00000000-0000-7000-8000-000000000002', 'ENG', 'Engineering')
ON CONFLICT (id) DO NOTHING;
