DROP TABLE IF EXISTS payslips;
DROP TABLE IF EXISTS payroll_runs;
DROP TABLE IF EXISTS salary_components;
DROP TABLE IF EXISTS salary_structures;

DROP TABLE IF EXISTS leave_requests;
DROP TABLE IF EXISTS leave_balances;
DROP TABLE IF EXISTS leave_types;
DROP TABLE IF EXISTS attendance;

-- teams.lead_id points at employees, so that key goes before the table does.
ALTER TABLE teams DROP CONSTRAINT IF EXISTS teams_lead_fkey;

DROP TABLE IF EXISTS employees;
DROP TABLE IF EXISTS teams;
DROP TABLE IF EXISTS designations;
DROP TABLE IF EXISTS departments;
