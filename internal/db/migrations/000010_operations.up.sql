-- OPERATIONS: assets, document metadata and support tickets.

CREATE TABLE assets (
    organization_id  uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id               uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    asset_tag        text NOT NULL,
    name             text NOT NULL,
    category         text,
    status           asset_status NOT NULL DEFAULT 'in_stock',
    serial_number    text,
    -- Who currently holds it. Cleared rather than cascading when they leave:
    -- the asset outlives the employment.
    assigned_to      uuid,
    assigned_on      date,
    vendor_id        uuid,
    purchase_date    date,
    purchase_cost    numeric(18, 4) NOT NULL DEFAULT 0,
    -- Straight-line depreciation inputs; the book value is derived, not stored.
    salvage_value    numeric(18, 4) NOT NULL DEFAULT 0,
    useful_life_years smallint,
    warranty_until   date,
    location         text,
    notes            text,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    created_by       uuid,
    updated_by       uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, assigned_to)
        REFERENCES employees (organization_id, id) ON DELETE SET NULL (assigned_to),
    FOREIGN KEY (organization_id, vendor_id)
        REFERENCES vendors (organization_id, id) ON DELETE SET NULL (vendor_id)
);
CREATE UNIQUE INDEX assets_org_tag_key ON assets (organization_id, lower(asset_tag));
CREATE INDEX assets_org_assigned_idx ON assets (organization_id, assigned_to);

-- File metadata only. The bytes live in object storage under storage_key;
-- Postgres is a poor blob store and backups would balloon.
CREATE TABLE documents (
    organization_id   uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id                uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    -- Polymorphic owner: an invoice, an employee, a project. No foreign key,
    -- so the service layer enforces the link.
    entity_type       text NOT NULL,
    entity_id         uuid,
    file_name         text NOT NULL,
    storage_key       text NOT NULL,
    mime_type         text,
    size_bytes        bigint,
    checksum          text,
    -- Client-visible documents surface in /portal. Defaulting to internal means
    -- an upload is never accidentally exposed.
    visibility        document_visibility NOT NULL DEFAULT 'internal',
    uploaded_by       uuid,
    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now(),
    created_by        uuid,
    updated_by        uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, uploaded_by)
        REFERENCES users (organization_id, id) ON DELETE SET NULL (uploaded_by),
    CONSTRAINT documents_size_check CHECK (size_bytes IS NULL OR size_bytes >= 0)
);
CREATE UNIQUE INDEX documents_org_storage_key ON documents (organization_id, storage_key);
CREATE INDEX documents_org_entity_idx ON documents (organization_id, entity_type, entity_id);

CREATE TABLE tickets (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    client_id       uuid,
    project_id      uuid,
    number          text NOT NULL,
    subject         text NOT NULL,
    description     text,
    status          ticket_status NOT NULL DEFAULT 'open',
    priority        priority_level NOT NULL DEFAULT 'medium',
    category        text,
    -- Raised by a portal user, worked by an employee.
    raised_by       uuid,
    assignee_id     uuid,
    -- SLA target and the moments measured against it.
    due_at          timestamptz,
    first_response_at timestamptz,
    resolved_at     timestamptz,
    closed_at       timestamptz,
    resolution      text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, client_id)
        REFERENCES clients (organization_id, id) ON DELETE SET NULL (client_id),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES projects (organization_id, id) ON DELETE SET NULL (project_id),
    FOREIGN KEY (organization_id, raised_by)
        REFERENCES users (organization_id, id) ON DELETE SET NULL (raised_by),
    FOREIGN KEY (organization_id, assignee_id)
        REFERENCES employees (organization_id, id) ON DELETE SET NULL (assignee_id)
);
CREATE UNIQUE INDEX tickets_org_number_key ON tickets (organization_id, lower(number));
CREATE INDEX tickets_org_status_idx ON tickets (organization_id, status);
CREATE INDEX tickets_org_open_idx
    ON tickets (organization_id, due_at) WHERE status IN ('open', 'in_progress', 'waiting');
