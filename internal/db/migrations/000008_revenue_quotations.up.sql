-- REVENUE, part two: quotations. Placed after projects and tax rates, both of
-- which a quotation line references.

CREATE TABLE quotations (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    client_id       uuid NOT NULL,
    lead_id         uuid,
    project_id      uuid,
    number          text NOT NULL,
    revision        smallint NOT NULL DEFAULT 0,
    status          quotation_status NOT NULL DEFAULT 'draft',
    issue_date      date NOT NULL DEFAULT current_date,
    valid_until     date,
    currency        text NOT NULL DEFAULT 'INR',
    -- Destination state decides CGST+SGST versus IGST. Stored on the document
    -- rather than re-derived from the client, who may later move.
    place_of_supply text,
    is_interstate   boolean NOT NULL DEFAULT false,
    subtotal        numeric(18, 4) NOT NULL DEFAULT 0,
    discount_total  numeric(18, 4) NOT NULL DEFAULT 0,
    tax_total       numeric(18, 4) NOT NULL DEFAULT 0,
    round_off       numeric(18, 4) NOT NULL DEFAULT 0,
    total           numeric(18, 4) NOT NULL DEFAULT 0,
    terms           text,
    notes           text,
    sent_at         timestamptz,
    decided_at      timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, client_id) REFERENCES clients (organization_id, id),
    FOREIGN KEY (organization_id, lead_id)
        REFERENCES leads (organization_id, id) ON DELETE SET NULL (lead_id),
    FOREIGN KEY (organization_id, project_id)
        REFERENCES projects (organization_id, id) ON DELETE SET NULL (project_id)
);
CREATE UNIQUE INDEX quotations_org_number_key ON quotations (organization_id, lower(number), revision);
CREATE INDEX quotations_org_client_idx ON quotations (organization_id, client_id);
CREATE INDEX quotations_org_status_idx ON quotations (organization_id, status);

CREATE TABLE quotation_lines (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    quotation_id    uuid NOT NULL,
    tax_rate_id     uuid,
    line_no         smallint NOT NULL,
    description     text NOT NULL,
    -- HSN for goods, SAC for services. Mandatory on a GST document.
    hsn_sac         text,
    quantity        numeric(18, 4) NOT NULL DEFAULT 1,
    unit            text,
    unit_price      numeric(18, 4) NOT NULL DEFAULT 0,
    discount_pct    numeric(9, 4) NOT NULL DEFAULT 0,
    discount_amount numeric(18, 4) NOT NULL DEFAULT 0,
    taxable_value   numeric(18, 4) NOT NULL DEFAULT 0,
    -- Rate and amount are both stored: the master rate may change later, and a
    -- quoted line must keep the numbers it was quoted at.
    tax_rate        numeric(9, 4) NOT NULL DEFAULT 0,
    tax_amount      numeric(18, 4) NOT NULL DEFAULT 0,
    line_total      numeric(18, 4) NOT NULL DEFAULT 0,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, quotation_id)
        REFERENCES quotations (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, tax_rate_id)
        REFERENCES tax_rates (organization_id, id) ON DELETE SET NULL (tax_rate_id),
    CONSTRAINT quotation_lines_quantity_check CHECK (quantity > 0)
);
CREATE UNIQUE INDEX quotation_lines_line_key
    ON quotation_lines (organization_id, quotation_id, line_no);
