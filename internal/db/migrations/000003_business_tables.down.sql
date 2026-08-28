-- Reverses 000003. Dropped in reverse dependency order; CASCADE is deliberately
-- not used, so a table gaining a new child later fails loudly here rather than
-- silently taking it down too.

DROP TABLE IF EXISTS notifications;
DROP TABLE IF EXISTS documents;
DROP TABLE IF EXISTS approvals;
DROP TABLE IF EXISTS ticket_comments;
DROP TABLE IF EXISTS tickets;

DROP TABLE IF EXISTS expenses;
DROP TABLE IF EXISTS expense_categories;
DROP TABLE IF EXISTS vendors;

DROP TABLE IF EXISTS payments;
DROP TABLE IF EXISTS invoice_items;
DROP TABLE IF EXISTS invoices;
DROP TABLE IF EXISTS quotation_items;
DROP TABLE IF EXISTS quotations;
DROP TABLE IF EXISTS items;
DROP TABLE IF EXISTS tax_rates;

DROP TABLE IF EXISTS timesheets;
DROP TABLE IF EXISTS tasks;
DROP TABLE IF EXISTS milestones;
DROP TABLE IF EXISTS project_members;
DROP TABLE IF EXISTS projects;
DROP TABLE IF EXISTS client_contacts;
DROP TABLE IF EXISTS clients;

DROP TABLE IF EXISTS payslips;
DROP TABLE IF EXISTS payroll_runs;
DROP TABLE IF EXISTS salary_structures;
DROP TABLE IF EXISTS leave_requests;
DROP TABLE IF EXISTS leave_types;
DROP TABLE IF EXISTS attendance;

-- The employee columns and their composite keys go before designations, which
-- one of them references.
ALTER TABLE employees
    DROP CONSTRAINT IF EXISTS employees_manager_fkey,
    DROP CONSTRAINT IF EXISTS employees_designation_fkey,
    DROP COLUMN IF EXISTS designation_id,
    DROP COLUMN IF EXISTS manager_id,
    DROP COLUMN IF EXISTS phone,
    DROP COLUMN IF EXISTS pan,
    DROP COLUMN IF EXISTS aadhaar_last4,
    DROP COLUMN IF EXISTS pf_number,
    DROP COLUMN IF EXISTS esi_number,
    DROP COLUMN IF EXISTS bank_account,
    DROP COLUMN IF EXISTS bank_ifsc;

DROP TABLE IF EXISTS designations;

DROP TABLE IF EXISTS audit_logs;
DROP TABLE IF EXISTS sessions;
DROP TABLE IF EXISTS user_roles;
DROP TABLE IF EXISTS role_permissions;
DROP TABLE IF EXISTS roles;
DROP TABLE IF EXISTS users;

DROP TABLE IF EXISTS organization_subscriptions;
DROP TABLE IF EXISTS platform_users;
DROP TABLE IF EXISTS plans;

ALTER TABLE employees DROP CONSTRAINT IF EXISTS employees_org_id_key;

DROP INDEX IF EXISTS organizations_gstin_key;
ALTER TABLE organizations
    DROP COLUMN IF EXISTS legal_name,
    DROP COLUMN IF EXISTS gstin,
    DROP COLUMN IF EXISTS pan,
    DROP COLUMN IF EXISTS state_code,
    DROP COLUMN IF EXISTS address,
    DROP COLUMN IF EXISTS phone,
    DROP COLUMN IF EXISTS email;
