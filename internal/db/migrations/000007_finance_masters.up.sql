-- FINANCE, part one: the masters that documents reference.
--
-- Ordered before quotations and invoices rather than with the rest of finance,
-- because a quotation line carries a tax rate and an invoice posts to an
-- account. Splitting the group keeps every foreign key pointing backwards.

CREATE TABLE accounts (
    organization_id  uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id               uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    code             text NOT NULL,
    name             text NOT NULL,
    account_type     account_type NOT NULL,
    parent_id        uuid,
    -- Group accounts are headings and cannot be posted to directly.
    is_group         boolean NOT NULL DEFAULT false,
    is_active        boolean NOT NULL DEFAULT true,
    opening_balance  numeric(18, 4) NOT NULL DEFAULT 0,
    currency         text NOT NULL DEFAULT 'INR',
    description      text,
    created_at       timestamptz NOT NULL DEFAULT now(),
    updated_at       timestamptz NOT NULL DEFAULT now(),
    created_by       uuid,
    updated_by       uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, parent_id)
        REFERENCES accounts (organization_id, id) ON DELETE SET NULL (parent_id)
);
CREATE UNIQUE INDEX accounts_org_code_key ON accounts (organization_id, lower(code));
CREATE INDEX accounts_org_type_idx ON accounts (organization_id, account_type);

-- Accounting periods. A posting into a closed period must be refused, which is
-- why the state lives here rather than being inferred from a cut-off date.
CREATE TABLE periods (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    fy_label        text NOT NULL,
    period_year     smallint NOT NULL,
    period_month    smallint NOT NULL,
    starts_on       date NOT NULL,
    ends_on         date NOT NULL,
    status          period_status NOT NULL DEFAULT 'open',
    closed_at       timestamptz,
    closed_by       uuid,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    CONSTRAINT periods_month_check CHECK (period_month BETWEEN 1 AND 12),
    CONSTRAINT periods_range_check CHECK (ends_on >= starts_on)
);
CREATE UNIQUE INDEX periods_unique ON periods (organization_id, period_year, period_month);

CREATE TABLE tax_rates (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    code            text NOT NULL,
    name            text NOT NULL,
    kind            tax_kind NOT NULL DEFAULT 'gst',
    -- Total rate. For GST the split into CGST/SGST or IGST is decided per
    -- document by the place of supply, so only the total is stored here.
    rate            numeric(9, 4) NOT NULL DEFAULT 0,
    cess_rate       numeric(9, 4) NOT NULL DEFAULT 0,
    -- TDS section, e.g. 194J or 194C. Null for GST rows.
    tds_section     text,
    is_active       boolean NOT NULL DEFAULT true,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    CONSTRAINT tax_rates_rate_check CHECK (rate >= 0 AND rate <= 100)
);
CREATE UNIQUE INDEX tax_rates_org_code_key ON tax_rates (organization_id, lower(code));

CREATE TABLE vendors (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    code            text NOT NULL,
    name            text NOT NULL,
    legal_name      text,
    status          vendor_status NOT NULL DEFAULT 'active',
    gstin           text,
    pan             text,
    is_registered   boolean NOT NULL DEFAULT true,
    -- Default withholding for this vendor; a bill may override it.
    tds_section     text,
    tds_rate        numeric(9, 4) NOT NULL DEFAULT 0,
    state_code      text,
    address         text,
    city            text,
    postal_code     text,
    country         text NOT NULL DEFAULT 'IN',
    email           text,
    phone           text,
    bank_account    text,
    bank_ifsc       text,
    payment_terms   smallint NOT NULL DEFAULT 30,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id)
);
CREATE UNIQUE INDEX vendors_org_code_key ON vendors (organization_id, lower(code));
CREATE UNIQUE INDEX vendors_org_name_key ON vendors (organization_id, lower(name));
