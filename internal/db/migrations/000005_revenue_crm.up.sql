-- REVENUE, part one: the pipeline and the client record.
--
-- Split from quotations (000007) because projects sit between them: a project
-- belongs to a client, and a quotation may belong to a project. Creating
-- clients first keeps every foreign key pointing backwards.

CREATE TABLE enquiries (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    reference       text NOT NULL,
    contact_name    text NOT NULL,
    company_name    text,
    email           text,
    phone           text,
    -- Where it came from: website, referral, campaign name, trade show.
    source          text,
    subject         text,
    message         text,
    status          enquiry_status NOT NULL DEFAULT 'new',
    owner_id        uuid,
    received_at     timestamptz NOT NULL DEFAULT now(),
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, owner_id)
        REFERENCES employees (organization_id, id) ON DELETE SET NULL (owner_id)
);
CREATE UNIQUE INDEX enquiries_org_reference_key ON enquiries (organization_id, lower(reference));
CREATE INDEX enquiries_org_status_idx ON enquiries (organization_id, status);

CREATE TABLE clients (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    code            text NOT NULL,
    name            text NOT NULL,
    legal_name      text,
    status          client_status NOT NULL DEFAULT 'active',
    gstin           text,
    pan             text,
    -- Unregistered clients have no GSTIN and are billed without input credit.
    is_registered   boolean NOT NULL DEFAULT true,
    state_code      text,
    address         text,
    city            text,
    postal_code     text,
    country         text NOT NULL DEFAULT 'IN',
    email           text,
    phone           text,
    website         text,
    currency        text NOT NULL DEFAULT 'INR',
    -- Days from invoice date to due date.
    payment_terms   smallint NOT NULL DEFAULT 30,
    credit_limit    numeric(18, 4) NOT NULL DEFAULT 0,
    owner_id        uuid,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, owner_id)
        REFERENCES employees (organization_id, id) ON DELETE SET NULL (owner_id)
);
CREATE UNIQUE INDEX clients_org_code_key ON clients (organization_id, lower(code));
CREATE UNIQUE INDEX clients_org_name_key ON clients (organization_id, lower(name));

CREATE TABLE leads (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    enquiry_id      uuid,
    client_id       uuid,
    title           text NOT NULL,
    contact_name    text,
    email           text,
    phone           text,
    source          text,
    status          lead_status NOT NULL DEFAULT 'new',
    -- Expected value and the odds of winning it, kept apart so a weighted
    -- pipeline is a product rather than a stored guess.
    estimated_value numeric(18, 4) NOT NULL DEFAULT 0,
    probability     numeric(9, 4) NOT NULL DEFAULT 0,
    expected_close  date,
    owner_id        uuid,
    lost_reason     text,
    closed_at       timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, enquiry_id)
        REFERENCES enquiries (organization_id, id) ON DELETE SET NULL (enquiry_id),
    FOREIGN KEY (organization_id, client_id)
        REFERENCES clients (organization_id, id) ON DELETE SET NULL (client_id),
    FOREIGN KEY (organization_id, owner_id)
        REFERENCES employees (organization_id, id) ON DELETE SET NULL (owner_id),
    CONSTRAINT leads_probability_check CHECK (probability BETWEEN 0 AND 100)
);
CREATE INDEX leads_org_status_idx ON leads (organization_id, status);
CREATE INDEX leads_org_owner_idx  ON leads (organization_id, owner_id);

CREATE TABLE client_contacts (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    client_id       uuid NOT NULL,
    -- Set when this contact has a /portal login.
    user_id         uuid,
    full_name       text NOT NULL,
    designation     text,
    email           text,
    phone           text,
    is_primary      boolean NOT NULL DEFAULT false,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, client_id)
        REFERENCES clients (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, user_id)
        REFERENCES users (organization_id, id) ON DELETE SET NULL (user_id)
);
CREATE INDEX client_contacts_org_client_idx ON client_contacts (organization_id, client_id);
-- At most one primary contact per client.
CREATE UNIQUE INDEX client_contacts_primary_key
    ON client_contacts (organization_id, client_id) WHERE is_primary;
