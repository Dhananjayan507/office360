-- FINANCE, part two: the documents and the ledger they post to.

CREATE TABLE invoices (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    client_id       uuid NOT NULL,
    project_id      uuid,
    quotation_id    uuid,
    number          text NOT NULL,
    status          invoice_status NOT NULL DEFAULT 'draft',
    issue_date      date NOT NULL DEFAULT current_date,
    due_date        date,
    currency        text NOT NULL DEFAULT 'INR',
    exchange_rate   numeric(18, 4) NOT NULL DEFAULT 1,
    -- GST classification, frozen at issue. place_of_supply decides whether the
    -- tax splits into CGST+SGST (intra-state) or lands wholly in IGST.
    place_of_supply text,
    is_interstate   boolean NOT NULL DEFAULT false,
    reverse_charge  boolean NOT NULL DEFAULT false,
    is_export       boolean NOT NULL DEFAULT false,
    subtotal        numeric(18, 4) NOT NULL DEFAULT 0,
    discount_total  numeric(18, 4) NOT NULL DEFAULT 0,
    taxable_total   numeric(18, 4) NOT NULL DEFAULT 0,
    cgst_total      numeric(18, 4) NOT NULL DEFAULT 0,
    sgst_total      numeric(18, 4) NOT NULL DEFAULT 0,
    igst_total      numeric(18, 4) NOT NULL DEFAULT 0,
    cess_total      numeric(18, 4) NOT NULL DEFAULT 0,
    round_off       numeric(18, 4) NOT NULL DEFAULT 0,
    total           numeric(18, 4) NOT NULL DEFAULT 0,
    amount_paid     numeric(18, 4) NOT NULL DEFAULT 0,
    -- Kept as a column rather than a view: it is filtered and sorted on
    -- constantly, and recomputing it per row on every ageing report is waste.
    amount_due      numeric(18, 4) NOT NULL DEFAULT 0,
    terms           text,
    notes           text,
    issued_at       timestamptz,
    cancelled_at    timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, client_id) REFERENCES clients (organization_id, id),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES projects (organization_id, id) ON DELETE SET NULL (project_id),
    FOREIGN KEY (organization_id, quotation_id)
        REFERENCES quotations (organization_id, id) ON DELETE SET NULL (quotation_id)
);
-- Invoice numbers must be sequential within an organisation for GST filing, and
-- are only unique within one: two organisations may both issue INV-0001.
CREATE UNIQUE INDEX invoices_org_number_key ON invoices (organization_id, lower(number));
CREATE INDEX invoices_org_client_idx ON invoices (organization_id, client_id);
CREATE INDEX invoices_org_status_idx ON invoices (organization_id, status);
CREATE INDEX invoices_org_due_idx
    ON invoices (organization_id, due_date) WHERE status IN ('issued', 'partly_paid', 'overdue');

CREATE TABLE invoice_lines (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    invoice_id      uuid NOT NULL,
    tax_rate_id     uuid,
    line_no         smallint NOT NULL,
    description     text NOT NULL,
    hsn_sac         text,
    quantity        numeric(18, 4) NOT NULL DEFAULT 1,
    unit            text,
    unit_price      numeric(18, 4) NOT NULL DEFAULT 0,
    discount_pct    numeric(9, 4) NOT NULL DEFAULT 0,
    discount_amount numeric(18, 4) NOT NULL DEFAULT 0,
    taxable_value   numeric(18, 4) NOT NULL DEFAULT 0,
    -- Rates and amounts both stored per line. A filed invoice must keep the
    -- numbers it was filed with, whatever the master rate becomes later.
    cgst_rate       numeric(9, 4) NOT NULL DEFAULT 0,
    cgst_amount     numeric(18, 4) NOT NULL DEFAULT 0,
    sgst_rate       numeric(9, 4) NOT NULL DEFAULT 0,
    sgst_amount     numeric(18, 4) NOT NULL DEFAULT 0,
    igst_rate       numeric(9, 4) NOT NULL DEFAULT 0,
    igst_amount     numeric(18, 4) NOT NULL DEFAULT 0,
    cess_rate       numeric(9, 4) NOT NULL DEFAULT 0,
    cess_amount     numeric(18, 4) NOT NULL DEFAULT 0,
    line_total      numeric(18, 4) NOT NULL DEFAULT 0,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, invoice_id)
        REFERENCES invoices (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, tax_rate_id)
        REFERENCES tax_rates (organization_id, id) ON DELETE SET NULL (tax_rate_id),
    CONSTRAINT invoice_lines_quantity_check CHECK (quantity > 0)
);
CREATE UNIQUE INDEX invoice_lines_line_key ON invoice_lines (organization_id, invoice_id, line_no);

CREATE TABLE receipts (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    client_id       uuid NOT NULL,
    invoice_id      uuid,
    number          text NOT NULL,
    received_on     date NOT NULL DEFAULT current_date,
    amount          numeric(18, 4) NOT NULL,
    -- TDS the client withheld at source: the invoice is settled for more than
    -- the cash received, and the difference is claimed against tax later.
    tds_deducted    numeric(18, 4) NOT NULL DEFAULT 0,
    method          payment_method NOT NULL DEFAULT 'bank_transfer',
    reference       text,
    bank_account    text,
    notes           text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, client_id) REFERENCES clients (organization_id, id),
    FOREIGN KEY (organization_id, invoice_id)
        REFERENCES invoices (organization_id, id) ON DELETE SET NULL (invoice_id),
    CONSTRAINT receipts_amount_check CHECK (amount > 0)
);
CREATE UNIQUE INDEX receipts_org_number_key ON receipts (organization_id, lower(number));
CREATE INDEX receipts_org_invoice_idx ON receipts (organization_id, invoice_id);

CREATE TABLE vendor_bills (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    vendor_id       uuid NOT NULL,
    project_id      uuid,
    number          text NOT NULL,
    -- The vendor's own reference, which is what appears in GSTR-2B.
    vendor_ref      text,
    status          vendor_bill_status NOT NULL DEFAULT 'draft',
    bill_date       date NOT NULL DEFAULT current_date,
    due_date        date,
    place_of_supply text,
    is_interstate   boolean NOT NULL DEFAULT false,
    reverse_charge  boolean NOT NULL DEFAULT false,
    subtotal        numeric(18, 4) NOT NULL DEFAULT 0,
    taxable_total   numeric(18, 4) NOT NULL DEFAULT 0,
    cgst_total      numeric(18, 4) NOT NULL DEFAULT 0,
    sgst_total      numeric(18, 4) NOT NULL DEFAULT 0,
    igst_total      numeric(18, 4) NOT NULL DEFAULT 0,
    cess_total      numeric(18, 4) NOT NULL DEFAULT 0,
    tds_section     text,
    tds_rate        numeric(9, 4) NOT NULL DEFAULT 0,
    tds_amount      numeric(18, 4) NOT NULL DEFAULT 0,
    round_off       numeric(18, 4) NOT NULL DEFAULT 0,
    total           numeric(18, 4) NOT NULL DEFAULT 0,
    amount_paid     numeric(18, 4) NOT NULL DEFAULT 0,
    amount_due      numeric(18, 4) NOT NULL DEFAULT 0,
    notes           text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, vendor_id) REFERENCES vendors (organization_id, id),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES projects (organization_id, id) ON DELETE SET NULL (project_id)
);
CREATE UNIQUE INDEX vendor_bills_org_number_key ON vendor_bills (organization_id, lower(number));
CREATE INDEX vendor_bills_org_vendor_idx ON vendor_bills (organization_id, vendor_id);
CREATE INDEX vendor_bills_org_status_idx ON vendor_bills (organization_id, status);

CREATE TABLE expenses (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    employee_id     uuid,
    vendor_id       uuid,
    project_id      uuid,
    account_id      uuid,
    number          text NOT NULL,
    status          expense_status NOT NULL DEFAULT 'draft',
    incurred_on     date NOT NULL DEFAULT current_date,
    category        text,
    description     text NOT NULL,
    amount          numeric(18, 4) NOT NULL DEFAULT 0,
    -- Input GST is reclaimable, so it is tracked apart from the base amount.
    tax_amount      numeric(18, 4) NOT NULL DEFAULT 0,
    total           numeric(18, 4) NOT NULL DEFAULT 0,
    -- Rebillable to the client, and whether that has happened yet.
    is_billable     boolean NOT NULL DEFAULT false,
    invoiced_at     timestamptz,
    receipt_ref     text,
    approved_by     uuid,
    approved_at     timestamptz,
    reimbursed_at   timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, employee_id)
        REFERENCES employees (organization_id, id) ON DELETE SET NULL (employee_id),
    FOREIGN KEY (organization_id, vendor_id)
        REFERENCES vendors (organization_id, id) ON DELETE SET NULL (vendor_id),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES projects (organization_id, id) ON DELETE SET NULL (project_id),
    FOREIGN KEY (organization_id, account_id)
        REFERENCES accounts (organization_id, id) ON DELETE SET NULL (account_id),
    FOREIGN KEY (organization_id, approved_by)
        REFERENCES employees (organization_id, id) ON DELETE SET NULL (approved_by),
    CONSTRAINT expenses_amount_check CHECK (amount >= 0)
);
CREATE UNIQUE INDEX expenses_org_number_key ON expenses (organization_id, lower(number));
CREATE INDEX expenses_org_incurred_idx ON expenses (organization_id, incurred_on DESC);

-- --- ledger ------------------------------------------------------------------

-- Double-entry header. source_type/source_id are polymorphic — a journal may
-- originate from an invoice, a payslip or a manual entry — so they carry no
-- foreign key; the service layer owns that link.
CREATE TABLE journals (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    period_id       uuid,
    number          text NOT NULL,
    status          journal_status NOT NULL DEFAULT 'draft',
    entry_date      date NOT NULL DEFAULT current_date,
    narration       text,
    source_type     text,
    source_id       uuid,
    -- Equal by definition once posted; stored so the balance check is a cheap
    -- comparison rather than an aggregate over the lines.
    total_debit     numeric(18, 4) NOT NULL DEFAULT 0,
    total_credit    numeric(18, 4) NOT NULL DEFAULT 0,
    posted_at       timestamptz,
    -- A posted journal is never edited. A correction is a reversing entry that
    -- points back here.
    reversed_by     uuid,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, period_id)
        REFERENCES periods (organization_id, id) ON DELETE SET NULL (period_id),
    FOREIGN KEY (organization_id, reversed_by)
        REFERENCES journals (organization_id, id) ON DELETE SET NULL (reversed_by),
    CONSTRAINT journals_balanced_check
        CHECK (status <> 'posted' OR total_debit = total_credit)
);
CREATE UNIQUE INDEX journals_org_number_key ON journals (organization_id, lower(number));
CREATE INDEX journals_org_date_idx   ON journals (organization_id, entry_date DESC);
CREATE INDEX journals_org_source_idx ON journals (organization_id, source_type, source_id);

CREATE TABLE journal_lines (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    journal_id      uuid NOT NULL,
    account_id      uuid NOT NULL,
    line_no         smallint NOT NULL,
    debit           numeric(18, 4) NOT NULL DEFAULT 0,
    credit          numeric(18, 4) NOT NULL DEFAULT 0,
    description     text,
    -- Optional analysis dimensions, so a ledger can be sliced by who it was for.
    client_id       uuid,
    vendor_id       uuid,
    project_id      uuid,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, journal_id)
        REFERENCES journals (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, account_id) REFERENCES accounts (organization_id, id),
    FOREIGN KEY (organization_id, client_id)
        REFERENCES clients (organization_id, id) ON DELETE SET NULL (client_id),
    FOREIGN KEY (organization_id, vendor_id)
        REFERENCES vendors (organization_id, id) ON DELETE SET NULL (vendor_id),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES projects (organization_id, id) ON DELETE SET NULL (project_id),
    -- A line is one side or the other, never both and never neither.
    CONSTRAINT journal_lines_side_check CHECK (
        (debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0)
    )
);
CREATE UNIQUE INDEX journal_lines_line_key ON journal_lines (organization_id, journal_id, line_no);
CREATE INDEX journal_lines_org_account_idx ON journal_lines (organization_id, account_id);
