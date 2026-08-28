-- Day 2, part two: the business table set.
--
-- Conventions, applied without exception to every tenant-scoped table below:
--
--   1. organization_id is the FIRST column, NOT NULL, ON DELETE CASCADE.
--   2. Every unique constraint is scoped to the organisation. A globally unique
--      code, number or email is a bug — two organisations may both have an
--      invoice INV-001 and may both employ the same address.
--   3. Foreign keys between tenant tables are COMPOSITE, carrying
--      organization_id, so a row can never reference another tenant's row.
--   4. Every tenant table carries UNIQUE (organization_id, id) so it can be the
--      target of rule 3. It costs one index per table and means a later foreign
--      key needs no migration on the parent.
--
-- Money is numeric(14,2) throughout — never float. Rates are numeric(5,2).
-- Tables with no organization_id are platform-level and deliberately so; they
-- are marked PLATFORM below.

-- --- organisation profile ----------------------------------------------------

-- Statutory identifiers an Indian entity needs before it can raise an invoice.
ALTER TABLE organizations
    ADD COLUMN legal_name  text,
    ADD COLUMN gstin       text,
    ADD COLUMN pan         text,
    ADD COLUMN state_code  text,
    ADD COLUMN address     text,
    ADD COLUMN phone       text,
    ADD COLUMN email       text;

-- GSTIN is unique nationally, so this one is deliberately not org-scoped.
CREATE UNIQUE INDEX organizations_gstin_key ON organizations (gstin) WHERE gstin IS NOT NULL;

-- Referenced by employees, users and everything else keyed to a person.
ALTER TABLE employees ADD CONSTRAINT employees_org_id_key UNIQUE (organization_id, id);

-- --- platform ----------------------------------------------------------------

-- PLATFORM. Subscription tiers offered to organisations.
CREATE TABLE plans (
    id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    code           text NOT NULL UNIQUE,
    name           text NOT NULL,
    price_monthly  numeric(14, 2) NOT NULL DEFAULT 0,
    max_users      integer,
    features       jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_active      boolean NOT NULL DEFAULT true,
    created_at     timestamptz NOT NULL DEFAULT now(),
    updated_at     timestamptz NOT NULL DEFAULT now()
);

-- PLATFORM. Tech360 staff who operate /platform. Deliberately separate from
-- users: a platform operator is not a member of any organisation, and merging
-- the two is how a support login ends up with tenant data by accident.
CREATE TABLE platform_users (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email         text NOT NULL,
    full_name     text NOT NULL,
    password_hash text NOT NULL,
    role          text NOT NULL DEFAULT 'support',
    status        text NOT NULL DEFAULT 'active',
    last_login_at timestamptz,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT platform_users_role_check CHECK (role IN ('owner', 'engineer', 'support')),
    CONSTRAINT platform_users_status_check CHECK (status IN ('active', 'suspended'))
);
CREATE UNIQUE INDEX platform_users_email_key ON platform_users (lower(email));

CREATE TABLE organization_subscriptions (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    plan_id         uuid NOT NULL REFERENCES plans (id),
    status          text NOT NULL DEFAULT 'trial',
    started_on      date NOT NULL DEFAULT current_date,
    renews_on       date,
    cancelled_at    timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    CONSTRAINT organization_subscriptions_status_check
        CHECK (status IN ('trial', 'active', 'past_due', 'cancelled'))
);
-- One live subscription per organisation; historical rows stay for the record.
CREATE UNIQUE INDEX organization_subscriptions_live_key
    ON organization_subscriptions (organization_id)
    WHERE status IN ('trial', 'active', 'past_due');

-- --- identity and access -----------------------------------------------------

CREATE TABLE users (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    employee_id     uuid,
    email           text NOT NULL,
    full_name       text NOT NULL,
    password_hash   text NOT NULL,
    -- Which portal this account may sign in to. A client contact must never
    -- reach /app, so the distinction is stored, not inferred from a role name.
    portal          text NOT NULL DEFAULT 'app',
    status          text NOT NULL DEFAULT 'active',
    last_login_at   timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, employee_id)
        REFERENCES employees (organization_id, id) ON DELETE SET NULL (employee_id),
    CONSTRAINT users_portal_check CHECK (portal IN ('app', 'portal')),
    CONSTRAINT users_status_check CHECK (status IN ('active', 'invited', 'suspended'))
);
CREATE UNIQUE INDEX users_org_email_key ON users (organization_id, lower(email));

CREATE TABLE roles (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    code            text NOT NULL,
    name            text NOT NULL,
    -- System roles are seeded per organisation and may not be deleted.
    is_system       boolean NOT NULL DEFAULT false,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id)
);
CREATE UNIQUE INDEX roles_org_code_key ON roles (organization_id, lower(code));

-- The grain authz.Can(role, module, action) is decided against.
CREATE TABLE role_permissions (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    role_id         uuid NOT NULL,
    module          text NOT NULL,
    action          text NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, role_id)
        REFERENCES roles (organization_id, id) ON DELETE CASCADE,
    CONSTRAINT role_permissions_action_check
        CHECK (action IN ('read', 'create', 'update', 'delete', 'approve', 'export'))
);
CREATE UNIQUE INDEX role_permissions_unique
    ON role_permissions (organization_id, role_id, module, action);

CREATE TABLE user_roles (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    user_id         uuid NOT NULL,
    role_id         uuid NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, user_id) REFERENCES users (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, role_id) REFERENCES roles (organization_id, id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX user_roles_unique ON user_roles (organization_id, user_id, role_id);

-- Refresh tokens. Only the hash is stored, so a database leak does not hand
-- over live sessions.
CREATE TABLE sessions (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    user_id         uuid NOT NULL,
    token_hash      text NOT NULL,
    user_agent      text,
    ip              inet,
    expires_at      timestamptz NOT NULL,
    revoked_at      timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, user_id) REFERENCES users (organization_id, id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX sessions_token_hash_key ON sessions (token_hash);
CREATE INDEX sessions_org_user_idx ON sessions (organization_id, user_id);

-- Written inside the caller's transaction, so an audit row cannot survive a
-- rolled-back change. actor_id is left unconstrained on purpose: a deleted user
-- must not erase the record of what they did.
CREATE TABLE audit_logs (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    actor_id        uuid,
    actor_label     text NOT NULL,
    action          text NOT NULL,
    entity_type     text NOT NULL,
    entity_id       uuid,
    before          jsonb,
    after           jsonb,
    request_id      text,
    ip              inet,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id)
);
CREATE INDEX audit_logs_org_entity_idx ON audit_logs (organization_id, entity_type, entity_id);
CREATE INDEX audit_logs_org_created_idx ON audit_logs (organization_id, created_at DESC);

-- --- people ------------------------------------------------------------------

CREATE TABLE designations (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    name            text NOT NULL,
    grade           text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id)
);
CREATE UNIQUE INDEX designations_org_name_key ON designations (organization_id, lower(name));

ALTER TABLE employees
    ADD COLUMN designation_id uuid,
    ADD COLUMN manager_id     uuid,
    ADD COLUMN phone          text,
    ADD COLUMN pan            text,
    ADD COLUMN aadhaar_last4  text,
    ADD COLUMN pf_number      text,
    ADD COLUMN esi_number     text,
    ADD COLUMN bank_account   text,
    ADD COLUMN bank_ifsc      text,
    ADD CONSTRAINT employees_designation_fkey
        FOREIGN KEY (organization_id, designation_id)
        REFERENCES designations (organization_id, id) ON DELETE SET NULL (designation_id),
    -- Self-referencing, and still composite: a manager must be in the same org.
    ADD CONSTRAINT employees_manager_fkey
        FOREIGN KEY (organization_id, manager_id)
        REFERENCES employees (organization_id, id) ON DELETE SET NULL (manager_id);

CREATE TABLE attendance (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    employee_id     uuid NOT NULL,
    on_date         date NOT NULL,
    status          text NOT NULL DEFAULT 'present',
    check_in        timestamptz,
    check_out       timestamptz,
    hours           numeric(5, 2),
    note            text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, employee_id)
        REFERENCES employees (organization_id, id) ON DELETE CASCADE,
    CONSTRAINT attendance_status_check
        CHECK (status IN ('present', 'absent', 'half_day', 'leave', 'holiday', 'week_off'))
);
CREATE UNIQUE INDEX attendance_unique ON attendance (organization_id, employee_id, on_date);

CREATE TABLE leave_types (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    name            text NOT NULL,
    days_per_year   numeric(5, 2) NOT NULL DEFAULT 0,
    is_paid         boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id)
);
CREATE UNIQUE INDEX leave_types_org_name_key ON leave_types (organization_id, lower(name));

CREATE TABLE leave_requests (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    employee_id     uuid NOT NULL,
    leave_type_id   uuid NOT NULL,
    from_date       date NOT NULL,
    to_date         date NOT NULL,
    days            numeric(5, 2) NOT NULL,
    reason          text,
    status          text NOT NULL DEFAULT 'pending',
    decided_by      uuid,
    decided_at      timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, employee_id)
        REFERENCES employees (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, leave_type_id)
        REFERENCES leave_types (organization_id, id),
    FOREIGN KEY (organization_id, decided_by)
        REFERENCES employees (organization_id, id) ON DELETE SET NULL (decided_by),
    CONSTRAINT leave_requests_status_check
        CHECK (status IN ('pending', 'approved', 'rejected', 'cancelled')),
    CONSTRAINT leave_requests_range_check CHECK (to_date >= from_date)
);
CREATE INDEX leave_requests_org_employee_idx ON leave_requests (organization_id, employee_id);

CREATE TABLE salary_structures (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    employee_id     uuid NOT NULL,
    effective_from  date NOT NULL,
    ctc_annual      numeric(14, 2) NOT NULL,
    basic           numeric(14, 2) NOT NULL DEFAULT 0,
    hra             numeric(14, 2) NOT NULL DEFAULT 0,
    special_allow   numeric(14, 2) NOT NULL DEFAULT 0,
    other_allow     numeric(14, 2) NOT NULL DEFAULT 0,
    pf_applicable   boolean NOT NULL DEFAULT true,
    esi_applicable  boolean NOT NULL DEFAULT false,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, employee_id)
        REFERENCES employees (organization_id, id) ON DELETE CASCADE
);
-- One structure per employee per effective date; revisions are new rows.
CREATE UNIQUE INDEX salary_structures_unique
    ON salary_structures (organization_id, employee_id, effective_from);

CREATE TABLE payroll_runs (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    period_month    integer NOT NULL,
    period_year     integer NOT NULL,
    status          text NOT NULL DEFAULT 'draft',
    -- Once locked a run is immutable; corrections are a new run.
    locked_at       timestamptz,
    paid_at         timestamptz,
    total_gross     numeric(14, 2) NOT NULL DEFAULT 0,
    total_net       numeric(14, 2) NOT NULL DEFAULT 0,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    CONSTRAINT payroll_runs_status_check CHECK (status IN ('draft', 'locked', 'paid')),
    CONSTRAINT payroll_runs_month_check CHECK (period_month BETWEEN 1 AND 12)
);
CREATE UNIQUE INDEX payroll_runs_period_key
    ON payroll_runs (organization_id, period_year, period_month);

CREATE TABLE payslips (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    payroll_run_id  uuid NOT NULL,
    employee_id     uuid NOT NULL,
    days_paid       numeric(5, 2) NOT NULL DEFAULT 0,
    basic           numeric(14, 2) NOT NULL DEFAULT 0,
    hra             numeric(14, 2) NOT NULL DEFAULT 0,
    allowances      numeric(14, 2) NOT NULL DEFAULT 0,
    gross           numeric(14, 2) NOT NULL DEFAULT 0,
    pf_employee     numeric(14, 2) NOT NULL DEFAULT 0,
    pf_employer     numeric(14, 2) NOT NULL DEFAULT 0,
    esi_employee    numeric(14, 2) NOT NULL DEFAULT 0,
    esi_employer    numeric(14, 2) NOT NULL DEFAULT 0,
    professional_tax numeric(14, 2) NOT NULL DEFAULT 0,
    tds             numeric(14, 2) NOT NULL DEFAULT 0,
    other_deduction numeric(14, 2) NOT NULL DEFAULT 0,
    net_pay         numeric(14, 2) NOT NULL DEFAULT 0,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, payroll_run_id)
        REFERENCES payroll_runs (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, employee_id)
        REFERENCES employees (organization_id, id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX payslips_unique ON payslips (organization_id, payroll_run_id, employee_id);

-- --- clients and delivery ----------------------------------------------------

CREATE TABLE clients (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    name            text NOT NULL,
    legal_name      text,
    gstin           text,
    pan             text,
    state_code      text,
    address         text,
    email           text,
    phone           text,
    -- Unregistered clients have no GSTIN and are billed differently.
    is_registered   boolean NOT NULL DEFAULT true,
    status          text NOT NULL DEFAULT 'active',
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    CONSTRAINT clients_status_check CHECK (status IN ('active', 'inactive'))
);
CREATE UNIQUE INDEX clients_org_name_key ON clients (organization_id, lower(name));

CREATE TABLE client_contacts (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    client_id       uuid NOT NULL,
    user_id         uuid,
    full_name       text NOT NULL,
    email           text,
    phone           text,
    is_primary      boolean NOT NULL DEFAULT false,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, client_id)
        REFERENCES clients (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, user_id)
        REFERENCES users (organization_id, id) ON DELETE SET NULL (user_id)
);
CREATE INDEX client_contacts_org_client_idx ON client_contacts (organization_id, client_id);

CREATE TABLE projects (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    client_id       uuid,
    code            text NOT NULL,
    name            text NOT NULL,
    description     text,
    status          text NOT NULL DEFAULT 'planned',
    billing_type    text NOT NULL DEFAULT 'fixed',
    budget          numeric(14, 2),
    starts_on       date,
    ends_on         date,
    manager_id      uuid,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, client_id)
        REFERENCES clients (organization_id, id) ON DELETE SET NULL (client_id),
    FOREIGN KEY (organization_id, manager_id)
        REFERENCES employees (organization_id, id) ON DELETE SET NULL (manager_id),
    CONSTRAINT projects_status_check
        CHECK (status IN ('planned', 'active', 'on_hold', 'completed', 'cancelled')),
    CONSTRAINT projects_billing_check
        CHECK (billing_type IN ('fixed', 'time_and_material', 'retainer', 'internal'))
);
CREATE UNIQUE INDEX projects_org_code_key ON projects (organization_id, lower(code));

CREATE TABLE project_members (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    project_id      uuid NOT NULL,
    employee_id     uuid NOT NULL,
    role            text,
    allocation_pct  numeric(5, 2) NOT NULL DEFAULT 100,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES projects (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, employee_id)
        REFERENCES employees (organization_id, id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX project_members_unique
    ON project_members (organization_id, project_id, employee_id);

CREATE TABLE milestones (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    project_id      uuid NOT NULL,
    name            text NOT NULL,
    amount          numeric(14, 2),
    due_on          date,
    status          text NOT NULL DEFAULT 'pending',
    completed_at    timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES projects (organization_id, id) ON DELETE CASCADE,
    CONSTRAINT milestones_status_check
        CHECK (status IN ('pending', 'in_progress', 'completed', 'invoiced'))
);
CREATE INDEX milestones_org_project_idx ON milestones (organization_id, project_id);

CREATE TABLE tasks (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    project_id      uuid NOT NULL,
    milestone_id    uuid,
    parent_task_id  uuid,
    title           text NOT NULL,
    description     text,
    assignee_id     uuid,
    status          text NOT NULL DEFAULT 'todo',
    priority        text NOT NULL DEFAULT 'medium',
    estimate_hours  numeric(7, 2),
    due_on          date,
    completed_at    timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES projects (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, milestone_id)
        REFERENCES milestones (organization_id, id) ON DELETE SET NULL (milestone_id),
    FOREIGN KEY (organization_id, parent_task_id)
        REFERENCES tasks (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, assignee_id)
        REFERENCES employees (organization_id, id) ON DELETE SET NULL (assignee_id),
    CONSTRAINT tasks_status_check
        CHECK (status IN ('todo', 'in_progress', 'blocked', 'review', 'done', 'cancelled')),
    CONSTRAINT tasks_priority_check CHECK (priority IN ('low', 'medium', 'high', 'urgent'))
);
CREATE INDEX tasks_org_project_idx ON tasks (organization_id, project_id);
CREATE INDEX tasks_org_assignee_idx ON tasks (organization_id, assignee_id);

CREATE TABLE timesheets (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    employee_id     uuid NOT NULL,
    project_id      uuid NOT NULL,
    task_id         uuid,
    on_date         date NOT NULL,
    hours           numeric(5, 2) NOT NULL,
    -- Non-billable hours still cost money; they are reported, not discarded.
    is_billable     boolean NOT NULL DEFAULT true,
    note            text,
    status          text NOT NULL DEFAULT 'draft',
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, employee_id)
        REFERENCES employees (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, project_id)
        REFERENCES projects (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, task_id)
        REFERENCES tasks (organization_id, id) ON DELETE SET NULL (task_id),
    CONSTRAINT timesheets_status_check CHECK (status IN ('draft', 'submitted', 'approved', 'rejected')),
    CONSTRAINT timesheets_hours_check CHECK (hours > 0 AND hours <= 24)
);
CREATE INDEX timesheets_org_employee_date_idx ON timesheets (organization_id, employee_id, on_date);
CREATE INDEX timesheets_org_project_idx ON timesheets (organization_id, project_id);

-- --- revenue -----------------------------------------------------------------

CREATE TABLE tax_rates (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    name            text NOT NULL,
    rate            numeric(5, 2) NOT NULL,
    kind            text NOT NULL DEFAULT 'gst',
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    CONSTRAINT tax_rates_kind_check CHECK (kind IN ('gst', 'cess', 'tds'))
);
CREATE UNIQUE INDEX tax_rates_org_name_key ON tax_rates (organization_id, lower(name));

CREATE TABLE items (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    code            text NOT NULL,
    name            text NOT NULL,
    kind            text NOT NULL DEFAULT 'service',
    -- HSN for goods, SAC for services. Mandatory on a GST invoice.
    hsn_sac         text,
    unit            text NOT NULL DEFAULT 'nos',
    rate            numeric(14, 2) NOT NULL DEFAULT 0,
    tax_rate_id     uuid,
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, tax_rate_id)
        REFERENCES tax_rates (organization_id, id) ON DELETE SET NULL (tax_rate_id),
    CONSTRAINT items_kind_check CHECK (kind IN ('goods', 'service'))
);
CREATE UNIQUE INDEX items_org_code_key ON items (organization_id, lower(code));

CREATE TABLE quotations (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    client_id       uuid NOT NULL,
    project_id      uuid,
    number          text NOT NULL,
    issue_date      date NOT NULL DEFAULT current_date,
    valid_until     date,
    status          text NOT NULL DEFAULT 'draft',
    subtotal        numeric(14, 2) NOT NULL DEFAULT 0,
    tax_total       numeric(14, 2) NOT NULL DEFAULT 0,
    total           numeric(14, 2) NOT NULL DEFAULT 0,
    notes           text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, client_id) REFERENCES clients (organization_id, id),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES projects (organization_id, id) ON DELETE SET NULL (project_id),
    CONSTRAINT quotations_status_check
        CHECK (status IN ('draft', 'sent', 'accepted', 'rejected', 'expired'))
);
CREATE UNIQUE INDEX quotations_org_number_key ON quotations (organization_id, lower(number));

CREATE TABLE quotation_items (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    quotation_id    uuid NOT NULL,
    item_id         uuid,
    line_no         integer NOT NULL,
    description     text NOT NULL,
    hsn_sac         text,
    quantity        numeric(12, 3) NOT NULL DEFAULT 1,
    rate            numeric(14, 2) NOT NULL DEFAULT 0,
    discount_pct    numeric(5, 2) NOT NULL DEFAULT 0,
    taxable_value   numeric(14, 2) NOT NULL DEFAULT 0,
    tax_rate        numeric(5, 2) NOT NULL DEFAULT 0,
    tax_amount      numeric(14, 2) NOT NULL DEFAULT 0,
    line_total      numeric(14, 2) NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, quotation_id)
        REFERENCES quotations (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, item_id)
        REFERENCES items (organization_id, id) ON DELETE SET NULL (item_id)
);
CREATE UNIQUE INDEX quotation_items_line_key
    ON quotation_items (organization_id, quotation_id, line_no);

CREATE TABLE invoices (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    client_id       uuid NOT NULL,
    project_id      uuid,
    quotation_id    uuid,
    number          text NOT NULL,
    issue_date      date NOT NULL DEFAULT current_date,
    due_date        date,
    status          text NOT NULL DEFAULT 'draft',
    -- Destination state decides CGST+SGST versus IGST, so it is stored on the
    -- invoice rather than re-derived from the client, which may later change.
    place_of_supply text,
    is_interstate   boolean NOT NULL DEFAULT false,
    reverse_charge  boolean NOT NULL DEFAULT false,
    currency        text NOT NULL DEFAULT 'INR',
    subtotal        numeric(14, 2) NOT NULL DEFAULT 0,
    discount_total  numeric(14, 2) NOT NULL DEFAULT 0,
    cgst_total      numeric(14, 2) NOT NULL DEFAULT 0,
    sgst_total      numeric(14, 2) NOT NULL DEFAULT 0,
    igst_total      numeric(14, 2) NOT NULL DEFAULT 0,
    cess_total      numeric(14, 2) NOT NULL DEFAULT 0,
    round_off       numeric(14, 2) NOT NULL DEFAULT 0,
    total           numeric(14, 2) NOT NULL DEFAULT 0,
    amount_paid     numeric(14, 2) NOT NULL DEFAULT 0,
    notes           text,
    issued_at       timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, client_id) REFERENCES clients (organization_id, id),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES projects (organization_id, id) ON DELETE SET NULL (project_id),
    FOREIGN KEY (organization_id, quotation_id)
        REFERENCES quotations (organization_id, id) ON DELETE SET NULL (quotation_id),
    CONSTRAINT invoices_status_check
        CHECK (status IN ('draft', 'issued', 'partly_paid', 'paid', 'overdue', 'cancelled'))
);
-- Invoice numbers must be gapless per organisation for GST filing, and are only
-- unique within one — two organisations may both issue INV-001.
CREATE UNIQUE INDEX invoices_org_number_key ON invoices (organization_id, lower(number));
CREATE INDEX invoices_org_client_idx ON invoices (organization_id, client_id);
CREATE INDEX invoices_org_status_idx ON invoices (organization_id, status);

CREATE TABLE invoice_items (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    invoice_id      uuid NOT NULL,
    item_id         uuid,
    line_no         integer NOT NULL,
    description     text NOT NULL,
    hsn_sac         text,
    quantity        numeric(12, 3) NOT NULL DEFAULT 1,
    unit            text,
    rate            numeric(14, 2) NOT NULL DEFAULT 0,
    discount_pct    numeric(5, 2) NOT NULL DEFAULT 0,
    taxable_value   numeric(14, 2) NOT NULL DEFAULT 0,
    -- Rates and amounts are both stored: the rate can change later, and a
    -- filed invoice must keep the numbers it was filed with.
    cgst_rate       numeric(5, 2) NOT NULL DEFAULT 0,
    cgst_amount     numeric(14, 2) NOT NULL DEFAULT 0,
    sgst_rate       numeric(5, 2) NOT NULL DEFAULT 0,
    sgst_amount     numeric(14, 2) NOT NULL DEFAULT 0,
    igst_rate       numeric(5, 2) NOT NULL DEFAULT 0,
    igst_amount     numeric(14, 2) NOT NULL DEFAULT 0,
    cess_rate       numeric(5, 2) NOT NULL DEFAULT 0,
    cess_amount     numeric(14, 2) NOT NULL DEFAULT 0,
    line_total      numeric(14, 2) NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, invoice_id)
        REFERENCES invoices (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, item_id)
        REFERENCES items (organization_id, id) ON DELETE SET NULL (item_id)
);
CREATE UNIQUE INDEX invoice_items_line_key ON invoice_items (organization_id, invoice_id, line_no);

CREATE TABLE payments (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    client_id       uuid NOT NULL,
    invoice_id      uuid,
    received_on     date NOT NULL DEFAULT current_date,
    amount          numeric(14, 2) NOT NULL,
    -- TDS the client withheld: the invoice is settled but the cash is short.
    tds_deducted    numeric(14, 2) NOT NULL DEFAULT 0,
    method          text NOT NULL DEFAULT 'bank_transfer',
    reference       text,
    notes           text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, client_id) REFERENCES clients (organization_id, id),
    FOREIGN KEY (organization_id, invoice_id)
        REFERENCES invoices (organization_id, id) ON DELETE SET NULL (invoice_id),
    CONSTRAINT payments_method_check
        CHECK (method IN ('cash', 'cheque', 'bank_transfer', 'upi', 'card', 'other')),
    CONSTRAINT payments_amount_check CHECK (amount > 0)
);
CREATE INDEX payments_org_invoice_idx ON payments (organization_id, invoice_id);

-- --- finance -----------------------------------------------------------------

CREATE TABLE vendors (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    name            text NOT NULL,
    gstin           text,
    pan             text,
    state_code      text,
    address         text,
    email           text,
    phone           text,
    status          text NOT NULL DEFAULT 'active',
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    CONSTRAINT vendors_status_check CHECK (status IN ('active', 'inactive'))
);
CREATE UNIQUE INDEX vendors_org_name_key ON vendors (organization_id, lower(name));

CREATE TABLE expense_categories (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    name            text NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id)
);
CREATE UNIQUE INDEX expense_categories_org_name_key
    ON expense_categories (organization_id, lower(name));

CREATE TABLE expenses (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    vendor_id       uuid,
    category_id     uuid,
    project_id      uuid,
    incurred_on     date NOT NULL DEFAULT current_date,
    description     text NOT NULL,
    amount          numeric(14, 2) NOT NULL,
    -- Input GST is reclaimable, so it is tracked apart from the base amount.
    gst_amount      numeric(14, 2) NOT NULL DEFAULT 0,
    -- Section under which tax was withheld at source, e.g. 194J, 194C.
    tds_section     text,
    tds_rate        numeric(5, 2) NOT NULL DEFAULT 0,
    tds_amount      numeric(14, 2) NOT NULL DEFAULT 0,
    total           numeric(14, 2) NOT NULL DEFAULT 0,
    payment_status  text NOT NULL DEFAULT 'unpaid',
    is_billable     boolean NOT NULL DEFAULT false,
    receipt_ref     text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, vendor_id)
        REFERENCES vendors (organization_id, id) ON DELETE SET NULL (vendor_id),
    FOREIGN KEY (organization_id, category_id)
        REFERENCES expense_categories (organization_id, id) ON DELETE SET NULL (category_id),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES projects (organization_id, id) ON DELETE SET NULL (project_id),
    CONSTRAINT expenses_payment_status_check
        CHECK (payment_status IN ('unpaid', 'partly_paid', 'paid')),
    CONSTRAINT expenses_amount_check CHECK (amount >= 0)
);
CREATE INDEX expenses_org_incurred_idx ON expenses (organization_id, incurred_on DESC);

-- --- operations --------------------------------------------------------------

CREATE TABLE tickets (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    client_id       uuid,
    project_id      uuid,
    number          text NOT NULL,
    subject         text NOT NULL,
    description     text,
    raised_by       uuid,
    assignee_id     uuid,
    status          text NOT NULL DEFAULT 'open',
    priority        text NOT NULL DEFAULT 'medium',
    due_at          timestamptz,
    resolved_at     timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, client_id)
        REFERENCES clients (organization_id, id) ON DELETE SET NULL (client_id),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES projects (organization_id, id) ON DELETE SET NULL (project_id),
    FOREIGN KEY (organization_id, raised_by)
        REFERENCES users (organization_id, id) ON DELETE SET NULL (raised_by),
    FOREIGN KEY (organization_id, assignee_id)
        REFERENCES employees (organization_id, id) ON DELETE SET NULL (assignee_id),
    CONSTRAINT tickets_status_check
        CHECK (status IN ('open', 'in_progress', 'waiting', 'resolved', 'closed')),
    CONSTRAINT tickets_priority_check CHECK (priority IN ('low', 'medium', 'high', 'urgent'))
);
CREATE UNIQUE INDEX tickets_org_number_key ON tickets (organization_id, lower(number));
CREATE INDEX tickets_org_status_idx ON tickets (organization_id, status);

CREATE TABLE ticket_comments (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    ticket_id       uuid NOT NULL,
    author_id       uuid,
    body            text NOT NULL,
    -- Internal notes must never reach the client portal.
    is_internal     boolean NOT NULL DEFAULT false,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, ticket_id)
        REFERENCES tickets (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, author_id)
        REFERENCES users (organization_id, id) ON DELETE SET NULL (author_id)
);
CREATE INDEX ticket_comments_org_ticket_idx ON ticket_comments (organization_id, ticket_id);

-- Generic approval chain. entity_type/entity_id are polymorphic and so cannot
-- carry a foreign key; the service layer owns that integrity.
CREATE TABLE approvals (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    entity_type     text NOT NULL,
    entity_id       uuid NOT NULL,
    step_no         integer NOT NULL DEFAULT 1,
    approver_id     uuid,
    status          text NOT NULL DEFAULT 'pending',
    comment         text,
    decided_at      timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, approver_id)
        REFERENCES users (organization_id, id) ON DELETE SET NULL (approver_id),
    CONSTRAINT approvals_status_check
        CHECK (status IN ('pending', 'approved', 'rejected', 'skipped'))
);
CREATE UNIQUE INDEX approvals_step_key
    ON approvals (organization_id, entity_type, entity_id, step_no);

CREATE TABLE documents (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    entity_type     text NOT NULL,
    entity_id       uuid,
    file_name       text NOT NULL,
    -- Object-store key. Bytes never live in Postgres.
    storage_key     text NOT NULL,
    mime_type       text,
    size_bytes      bigint,
    uploaded_by     uuid,
    is_client_visible boolean NOT NULL DEFAULT false,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, uploaded_by)
        REFERENCES users (organization_id, id) ON DELETE SET NULL (uploaded_by)
);
CREATE INDEX documents_org_entity_idx ON documents (organization_id, entity_type, entity_id);

CREATE TABLE notifications (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT gen_random_uuid(),
    user_id         uuid NOT NULL,
    kind            text NOT NULL,
    title           text NOT NULL,
    body            text,
    link            text,
    read_at         timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (id),
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, user_id)
        REFERENCES users (organization_id, id) ON DELETE CASCADE
);
-- Partial: the unread badge is the hot query, and unread rows are the minority.
CREATE INDEX notifications_org_unread_idx
    ON notifications (organization_id, user_id) WHERE read_at IS NULL;
