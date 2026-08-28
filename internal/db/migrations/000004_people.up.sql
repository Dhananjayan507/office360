-- PEOPLE: org structure, employee records, attendance, leave and payroll.

CREATE TABLE departments (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    code            text,
    name            text NOT NULL,
    parent_id       uuid,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    -- Self-referencing and still composite: a parent department must be in the
    -- same organisation.
    FOREIGN KEY (organization_id, parent_id)
        REFERENCES departments (organization_id, id) ON DELETE SET NULL (parent_id)
);
CREATE UNIQUE INDEX departments_org_name_key ON departments (organization_id, lower(name));

CREATE TABLE designations (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    name            text NOT NULL,
    grade           text,
    level           smallint,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id)
);
CREATE UNIQUE INDEX designations_org_name_key ON designations (organization_id, lower(name));

-- Created before employees, but its lead_id foreign key is added after them:
-- teams and employees reference each other.
CREATE TABLE teams (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    department_id   uuid,
    name            text NOT NULL,
    lead_id         uuid,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, department_id)
        REFERENCES departments (organization_id, id) ON DELETE SET NULL (department_id)
);
CREATE UNIQUE INDEX teams_org_name_key ON teams (organization_id, lower(name));

CREATE TABLE employees (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    employee_code   text NOT NULL,
    user_id         uuid,
    department_id   uuid,
    team_id         uuid,
    designation_id  uuid,
    manager_id      uuid,
    full_name       text NOT NULL,
    email           text NOT NULL,
    phone           text,
    gender          gender_type NOT NULL DEFAULT 'undisclosed',
    date_of_birth   date,
    status          employee_status NOT NULL DEFAULT 'probation',
    employment_type employment_type NOT NULL DEFAULT 'full_time',
    hired_on        date,
    confirmed_on    date,
    exited_on       date,
    -- Statutory identifiers. Aadhaar is stored as the last four digits only:
    -- the full number is not needed for payroll and is a liability at rest.
    pan             text,
    aadhaar_last4   text,
    uan             text,
    pf_number       text,
    esi_number      text,
    bank_account    text,
    bank_ifsc       text,
    address         text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, user_id)
        REFERENCES users (organization_id, id) ON DELETE SET NULL (user_id),
    FOREIGN KEY (organization_id, department_id)
        REFERENCES departments (organization_id, id) ON DELETE SET NULL (department_id),
    FOREIGN KEY (organization_id, team_id)
        REFERENCES teams (organization_id, id) ON DELETE SET NULL (team_id),
    FOREIGN KEY (organization_id, designation_id)
        REFERENCES designations (organization_id, id) ON DELETE SET NULL (designation_id),
    FOREIGN KEY (organization_id, manager_id)
        REFERENCES employees (organization_id, id) ON DELETE SET NULL (manager_id),
    CONSTRAINT employees_aadhaar_check CHECK (aadhaar_last4 IS NULL OR aadhaar_last4 ~ '^[0-9]{4}$'),
    CONSTRAINT employees_exit_check CHECK (exited_on IS NULL OR hired_on IS NULL OR exited_on >= hired_on)
);
CREATE UNIQUE INDEX employees_org_code_key  ON employees (organization_id, lower(employee_code));
CREATE UNIQUE INDEX employees_org_email_key ON employees (organization_id, lower(email));
CREATE INDEX employees_org_department_idx   ON employees (organization_id, department_id);
CREATE INDEX employees_org_status_idx       ON employees (organization_id, status);

ALTER TABLE teams ADD CONSTRAINT teams_lead_fkey
    FOREIGN KEY (organization_id, lead_id)
    REFERENCES employees (organization_id, id) ON DELETE SET NULL (lead_id);

-- --- attendance and leave ----------------------------------------------------

CREATE TABLE attendance (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    employee_id     uuid NOT NULL,
    on_date         date NOT NULL,
    status          attendance_status NOT NULL DEFAULT 'present',
    check_in        timestamptz,
    check_out       timestamptz,
    worked_hours    numeric(9, 4) NOT NULL DEFAULT 0,
    overtime_hours  numeric(9, 4) NOT NULL DEFAULT 0,
    note            text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, employee_id)
        REFERENCES employees (organization_id, id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX attendance_unique ON attendance (organization_id, employee_id, on_date);
CREATE INDEX attendance_org_date_idx ON attendance (organization_id, on_date);

CREATE TABLE leave_types (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    code            text NOT NULL,
    name            text NOT NULL,
    days_per_year   numeric(9, 4) NOT NULL DEFAULT 0,
    is_paid         boolean NOT NULL DEFAULT true,
    -- Unused days roll into next year's balance when true.
    carry_forward   boolean NOT NULL DEFAULT false,
    max_carry_days  numeric(9, 4) NOT NULL DEFAULT 0,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id)
);
CREATE UNIQUE INDEX leave_types_org_code_key ON leave_types (organization_id, lower(code));

CREATE TABLE leave_balances (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    employee_id     uuid NOT NULL,
    leave_type_id   uuid NOT NULL,
    fy_label        text NOT NULL,
    entitled_days   numeric(9, 4) NOT NULL DEFAULT 0,
    carried_days    numeric(9, 4) NOT NULL DEFAULT 0,
    used_days       numeric(9, 4) NOT NULL DEFAULT 0,
    -- Approved but not yet taken, so a second request cannot spend it twice.
    pending_days    numeric(9, 4) NOT NULL DEFAULT 0,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, employee_id)
        REFERENCES employees (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, leave_type_id)
        REFERENCES leave_types (organization_id, id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX leave_balances_unique
    ON leave_balances (organization_id, employee_id, leave_type_id, fy_label);

CREATE TABLE leave_requests (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    employee_id     uuid NOT NULL,
    leave_type_id   uuid NOT NULL,
    from_date       date NOT NULL,
    to_date         date NOT NULL,
    days            numeric(9, 4) NOT NULL,
    reason          text,
    status          leave_request_status NOT NULL DEFAULT 'pending',
    decided_by      uuid,
    decided_at      timestamptz,
    decision_note   text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, employee_id)
        REFERENCES employees (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, leave_type_id)
        REFERENCES leave_types (organization_id, id),
    FOREIGN KEY (organization_id, decided_by)
        REFERENCES employees (organization_id, id) ON DELETE SET NULL (decided_by),
    CONSTRAINT leave_requests_range_check CHECK (to_date >= from_date),
    CONSTRAINT leave_requests_days_check CHECK (days > 0)
);
CREATE INDEX leave_requests_org_employee_idx ON leave_requests (organization_id, employee_id);
CREATE INDEX leave_requests_org_status_idx   ON leave_requests (organization_id, status);

-- --- payroll -----------------------------------------------------------------

CREATE TABLE salary_structures (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    employee_id     uuid NOT NULL,
    effective_from  date NOT NULL,
    effective_to    date,
    ctc_annual      numeric(18, 4) NOT NULL DEFAULT 0,
    gross_monthly   numeric(18, 4) NOT NULL DEFAULT 0,
    pf_applicable   boolean NOT NULL DEFAULT true,
    esi_applicable  boolean NOT NULL DEFAULT false,
    pt_applicable   boolean NOT NULL DEFAULT true,
    notes           text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, employee_id)
        REFERENCES employees (organization_id, id) ON DELETE CASCADE,
    CONSTRAINT salary_structures_period_check
        CHECK (effective_to IS NULL OR effective_to >= effective_from)
);
-- A revision is a new row, so one structure per employee per start date.
CREATE UNIQUE INDEX salary_structures_unique
    ON salary_structures (organization_id, employee_id, effective_from);

-- The lines of a salary structure: basic, HRA, PF, professional tax and so on.
CREATE TABLE salary_components (
    organization_id     uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id                  uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    salary_structure_id uuid NOT NULL,
    code                text NOT NULL,
    name                text NOT NULL,
    component_type      salary_component_type NOT NULL,
    amount_monthly      numeric(18, 4) NOT NULL DEFAULT 0,
    -- Set when the component is a percentage of another, e.g. HRA at 40% of
    -- basic. The resolved figure is still written to amount_monthly.
    percent_of          text,
    percent_rate        numeric(9, 4),
    is_taxable          boolean NOT NULL DEFAULT true,
    sequence            smallint NOT NULL DEFAULT 0,
    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),
    created_by          uuid,
    updated_by          uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, salary_structure_id)
        REFERENCES salary_structures (organization_id, id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX salary_components_unique
    ON salary_components (organization_id, salary_structure_id, lower(code));

CREATE TABLE payroll_runs (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    period_year     smallint NOT NULL,
    period_month    smallint NOT NULL,
    status          payroll_run_status NOT NULL DEFAULT 'draft',
    -- Once locked a run is immutable; a correction is a fresh run.
    locked_at       timestamptz,
    paid_at         timestamptz,
    employee_count  integer NOT NULL DEFAULT 0,
    total_gross     numeric(18, 4) NOT NULL DEFAULT 0,
    total_deduction numeric(18, 4) NOT NULL DEFAULT 0,
    total_net       numeric(18, 4) NOT NULL DEFAULT 0,
    notes           text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    CONSTRAINT payroll_runs_month_check CHECK (period_month BETWEEN 1 AND 12)
);
CREATE UNIQUE INDEX payroll_runs_period_key
    ON payroll_runs (organization_id, period_year, period_month);

CREATE TABLE payslips (
    organization_id  uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id               uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    payroll_run_id   uuid NOT NULL,
    employee_id      uuid NOT NULL,
    payable_days     numeric(9, 4) NOT NULL DEFAULT 0,
    lop_days         numeric(9, 4) NOT NULL DEFAULT 0,
    basic            numeric(18, 4) NOT NULL DEFAULT 0,
    hra              numeric(18, 4) NOT NULL DEFAULT 0,
    allowances       numeric(18, 4) NOT NULL DEFAULT 0,
    overtime         numeric(18, 4) NOT NULL DEFAULT 0,
    gross            numeric(18, 4) NOT NULL DEFAULT 0,
    -- Statutory deductions kept apart, because each is filed separately.
    pf_employee      numeric(18, 4) NOT NULL DEFAULT 0,
    pf_employer      numeric(18, 4) NOT NULL DEFAULT 0,
    esi_employee     numeric(18, 4) NOT NULL DEFAULT 0,
    esi_employer     numeric(18, 4) NOT NULL DEFAULT 0,
    professional_tax numeric(18, 4) NOT NULL DEFAULT 0,
    tds              numeric(18, 4) NOT NULL DEFAULT 0,
    other_deduction  numeric(18, 4) NOT NULL DEFAULT 0,
    total_deduction  numeric(18, 4) NOT NULL DEFAULT 0,
    net_pay          numeric(18, 4) NOT NULL DEFAULT 0,
    -- Frozen copy of the component breakdown as it stood when the run locked.
    breakdown        jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    created_by       uuid,
    updated_by       uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, payroll_run_id)
        REFERENCES payroll_runs (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, employee_id)
        REFERENCES employees (organization_id, id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX payslips_unique ON payslips (organization_id, payroll_run_id, employee_id);
CREATE INDEX payslips_org_employee_idx ON payslips (organization_id, employee_id);
