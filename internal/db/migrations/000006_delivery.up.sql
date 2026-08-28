-- DELIVERY: projects, their people, and the work tracked against them.

CREATE TABLE projects (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    client_id       uuid,
    code            text NOT NULL,
    name            text NOT NULL,
    description     text,
    status          project_status NOT NULL DEFAULT 'planned',
    billing_type    billing_type NOT NULL DEFAULT 'fixed',
    -- Contract value for fixed-price work; the hourly rate for T&M.
    contract_value  numeric(18, 4) NOT NULL DEFAULT 0,
    hourly_rate     numeric(18, 4) NOT NULL DEFAULT 0,
    budget_hours    numeric(9, 4) NOT NULL DEFAULT 0,
    currency        text NOT NULL DEFAULT 'INR',
    starts_on       date,
    ends_on         date,
    manager_id      uuid,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, client_id)
        REFERENCES clients (organization_id, id) ON DELETE SET NULL (client_id),
    FOREIGN KEY (organization_id, manager_id)
        REFERENCES employees (organization_id, id) ON DELETE SET NULL (manager_id),
    CONSTRAINT projects_dates_check CHECK (ends_on IS NULL OR starts_on IS NULL OR ends_on >= starts_on)
);
CREATE UNIQUE INDEX projects_org_code_key ON projects (organization_id, lower(code));
CREATE INDEX projects_org_client_idx ON projects (organization_id, client_id);
CREATE INDEX projects_org_status_idx ON projects (organization_id, status);

CREATE TABLE project_members (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    project_id      uuid NOT NULL,
    employee_id     uuid NOT NULL,
    role            text,
    -- Percentage of the person's capacity, and what their time bills at on
    -- this project, which may differ from the project default.
    allocation_pct  numeric(9, 4) NOT NULL DEFAULT 100,
    bill_rate       numeric(18, 4) NOT NULL DEFAULT 0,
    joined_on       date,
    left_on         date,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES projects (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, employee_id)
        REFERENCES employees (organization_id, id) ON DELETE CASCADE,
    CONSTRAINT project_members_allocation_check CHECK (allocation_pct BETWEEN 0 AND 100)
);
CREATE UNIQUE INDEX project_members_unique
    ON project_members (organization_id, project_id, employee_id);

CREATE TABLE milestones (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    project_id      uuid NOT NULL,
    name            text NOT NULL,
    description     text,
    status          milestone_status NOT NULL DEFAULT 'pending',
    -- What becomes invoiceable when this milestone completes.
    amount          numeric(18, 4) NOT NULL DEFAULT 0,
    due_on          date,
    completed_at    timestamptz,
    sequence        smallint NOT NULL DEFAULT 0,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES projects (organization_id, id) ON DELETE CASCADE
);
CREATE INDEX milestones_org_project_idx ON milestones (organization_id, project_id);

CREATE TABLE tasks (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    project_id      uuid NOT NULL,
    milestone_id    uuid,
    parent_task_id  uuid,
    reference       text,
    title           text NOT NULL,
    description     text,
    status          task_status NOT NULL DEFAULT 'todo',
    priority        priority_level NOT NULL DEFAULT 'medium',
    assignee_id     uuid,
    estimate_hours  numeric(9, 4) NOT NULL DEFAULT 0,
    logged_hours    numeric(9, 4) NOT NULL DEFAULT 0,
    starts_on       date,
    due_on          date,
    completed_at    timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES projects (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, milestone_id)
        REFERENCES milestones (organization_id, id) ON DELETE SET NULL (milestone_id),
    -- Subtasks die with their parent, and must share its organisation.
    FOREIGN KEY (organization_id, parent_task_id)
        REFERENCES tasks (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, assignee_id)
        REFERENCES employees (organization_id, id) ON DELETE SET NULL (assignee_id)
);
CREATE INDEX tasks_org_project_idx  ON tasks (organization_id, project_id);
CREATE INDEX tasks_org_assignee_idx ON tasks (organization_id, assignee_id);
CREATE INDEX tasks_org_status_idx   ON tasks (organization_id, status);

CREATE TABLE timesheets (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    employee_id     uuid NOT NULL,
    project_id      uuid NOT NULL,
    task_id         uuid,
    on_date         date NOT NULL,
    hours           numeric(9, 4) NOT NULL,
    -- Non-billable hours still cost money, so they are recorded and reported
    -- rather than discarded at entry.
    is_billable     boolean NOT NULL DEFAULT true,
    bill_rate       numeric(18, 4) NOT NULL DEFAULT 0,
    billable_amount numeric(18, 4) NOT NULL DEFAULT 0,
    -- Set once the line has been carried onto an invoice, so it is not billed
    -- twice. No foreign key: invoices are created two migrations later.
    invoiced_at     timestamptz,
    description     text,
    status          timesheet_status NOT NULL DEFAULT 'draft',
    approved_by     uuid,
    approved_at     timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, employee_id)
        REFERENCES employees (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, project_id)
        REFERENCES projects (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, task_id)
        REFERENCES tasks (organization_id, id) ON DELETE SET NULL (task_id),
    FOREIGN KEY (organization_id, approved_by)
        REFERENCES employees (organization_id, id) ON DELETE SET NULL (approved_by),
    CONSTRAINT timesheets_hours_check CHECK (hours > 0 AND hours <= 24)
);
CREATE INDEX timesheets_org_employee_date_idx ON timesheets (organization_id, employee_id, on_date);
CREATE INDEX timesheets_org_project_idx       ON timesheets (organization_id, project_id);
CREATE INDEX timesheets_org_unbilled_idx
    ON timesheets (organization_id, project_id) WHERE is_billable AND invoiced_at IS NULL;
