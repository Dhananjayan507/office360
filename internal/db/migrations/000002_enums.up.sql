-- Postgres enum types for every closed value set in the schema.
--
-- Enums rather than text + CHECK: the type is enforced everywhere the column is
-- used, including in function signatures and casts, and sqlc generates a real Go
-- type for each one instead of a bare string. The cost is that adding a value
-- needs ALTER TYPE ... ADD VALUE, and removing one needs a full type rebuild —
-- which is the right trade for value sets that genuinely are closed.

-- --- platform ---
CREATE TYPE organization_status AS ENUM ('active', 'suspended', 'closed');
CREATE TYPE user_status         AS ENUM ('active', 'invited', 'suspended', 'locked');
-- Which portal an account may sign in to. Stored, never inferred from a role
-- name: a client contact must never reach /app.
CREATE TYPE portal_type         AS ENUM ('platform', 'app', 'portal');
CREATE TYPE plan_interval       AS ENUM ('monthly', 'quarterly', 'yearly');
CREATE TYPE audit_action        AS ENUM ('create', 'update', 'delete', 'login', 'logout', 'export', 'approve', 'reject');
CREATE TYPE number_kind         AS ENUM ('invoice', 'credit_note', 'quotation', 'receipt', 'vendor_bill', 'expense', 'ticket', 'project', 'employee', 'journal');

-- --- people ---
CREATE TYPE employee_status     AS ENUM ('probation', 'active', 'on_leave', 'notice', 'exited');
CREATE TYPE employment_type     AS ENUM ('full_time', 'part_time', 'contract', 'intern', 'consultant');
CREATE TYPE gender_type         AS ENUM ('male', 'female', 'other', 'undisclosed');
CREATE TYPE attendance_status   AS ENUM ('present', 'absent', 'half_day', 'leave', 'holiday', 'week_off');
CREATE TYPE leave_request_status AS ENUM ('pending', 'approved', 'rejected', 'cancelled');
CREATE TYPE salary_component_type AS ENUM ('earning', 'deduction', 'employer_contribution');
CREATE TYPE payroll_run_status  AS ENUM ('draft', 'processing', 'locked', 'paid');

-- --- delivery ---
CREATE TYPE project_status      AS ENUM ('planned', 'active', 'on_hold', 'completed', 'cancelled');
CREATE TYPE billing_type        AS ENUM ('fixed', 'time_and_material', 'retainer', 'internal');
CREATE TYPE milestone_status    AS ENUM ('pending', 'in_progress', 'completed', 'invoiced');
CREATE TYPE task_status         AS ENUM ('todo', 'in_progress', 'blocked', 'review', 'done', 'cancelled');
CREATE TYPE priority_level      AS ENUM ('low', 'medium', 'high', 'urgent');
CREATE TYPE timesheet_status    AS ENUM ('draft', 'submitted', 'approved', 'rejected');

-- --- revenue ---
CREATE TYPE enquiry_status      AS ENUM ('new', 'contacted', 'qualified', 'converted', 'dropped');
CREATE TYPE lead_status         AS ENUM ('new', 'contacted', 'qualified', 'proposal', 'negotiation', 'won', 'lost');
CREATE TYPE client_status       AS ENUM ('active', 'inactive', 'blacklisted');
CREATE TYPE quotation_status    AS ENUM ('draft', 'sent', 'accepted', 'rejected', 'expired');

-- --- finance ---
CREATE TYPE invoice_status      AS ENUM ('draft', 'issued', 'partly_paid', 'paid', 'overdue', 'cancelled');
CREATE TYPE payment_method      AS ENUM ('cash', 'cheque', 'bank_transfer', 'upi', 'card', 'other');
CREATE TYPE vendor_status       AS ENUM ('active', 'inactive', 'blacklisted');
CREATE TYPE vendor_bill_status  AS ENUM ('draft', 'received', 'approved', 'partly_paid', 'paid', 'cancelled');
CREATE TYPE expense_status      AS ENUM ('draft', 'submitted', 'approved', 'reimbursed', 'rejected');
CREATE TYPE tax_kind            AS ENUM ('gst', 'cess', 'tds', 'tcs');
CREATE TYPE account_type        AS ENUM ('asset', 'liability', 'equity', 'income', 'expense');
CREATE TYPE journal_status      AS ENUM ('draft', 'posted', 'reversed');
CREATE TYPE period_status       AS ENUM ('open', 'closed', 'locked');

-- --- operations ---
CREATE TYPE asset_status        AS ENUM ('in_stock', 'assigned', 'under_repair', 'retired', 'lost');
CREATE TYPE ticket_status       AS ENUM ('open', 'in_progress', 'waiting', 'resolved', 'closed');
CREATE TYPE document_visibility AS ENUM ('internal', 'client');
