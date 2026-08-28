-- PLATFORM: tenancy, identity, access, audit and per-organisation configuration.
--
-- Conventions applied to every business table in this and later migrations:
--
--   * organization_id uuid NOT NULL is the FIRST column, ON DELETE CASCADE.
--   * id uuid PRIMARY KEY DEFAULT uuid_generate_v7().
--   * created_at / updated_at timestamptz NOT NULL DEFAULT now().
--   * created_by / updated_by uuid, deliberately WITHOUT a foreign key — the
--     actor may be a tenant user, a platform operator or a background job, and
--     provenance must survive that account being deleted.
--   * UNIQUE (organization_id, id) so the table can be the target of the
--     composite foreign keys described below.
--   * Every unique constraint is scoped to the organisation. Two organisations
--     may both issue INV-001 and may both employ the same email address.
--   * Every foreign key between business tables is COMPOSITE, carrying
--     organization_id, so a row can never reference another tenant's row even
--     if the service layer forgets to check.
--
-- Money is NUMERIC(18,4) throughout. Rates and percentages are NUMERIC(9,4).
--
-- Two tables have no organization_id and that is deliberate: organizations is
-- the tenant root, and plans is a platform-wide catalogue.

-- --- tenant root -------------------------------------------------------------

CREATE TABLE organizations (
    id          uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    name        text NOT NULL,
    slug        text NOT NULL,
    legal_name  text,
    status      organization_status NOT NULL DEFAULT 'active',
    gstin       text,
    pan         text,
    state_code  text,
    address     text,
    city        text,
    postal_code text,
    country     text NOT NULL DEFAULT 'IN',
    phone       text,
    email       text,
    currency    text NOT NULL DEFAULT 'INR',
    timezone    text NOT NULL DEFAULT 'Asia/Kolkata',
    -- Financial year start month; 4 = April, the Indian default.
    fy_start_month smallint NOT NULL DEFAULT 4,
    created_at  timestamptz NOT NULL DEFAULT now(),
    updated_at  timestamptz NOT NULL DEFAULT now(),
    created_by  uuid,
    updated_by  uuid,
    CONSTRAINT organizations_fy_month_check CHECK (fy_start_month BETWEEN 1 AND 12)
);
CREATE UNIQUE INDEX organizations_slug_key ON organizations (lower(slug));
-- A GSTIN identifies a legal entity nationally, so this one is not org-scoped.
CREATE UNIQUE INDEX organizations_gstin_key ON organizations (gstin) WHERE gstin IS NOT NULL;

-- --- platform catalogue ------------------------------------------------------

CREATE TABLE plans (
    id            uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    code          text NOT NULL,
    name          text NOT NULL,
    price         numeric(18, 4) NOT NULL DEFAULT 0,
    interval      plan_interval NOT NULL DEFAULT 'monthly',
    max_users     integer,
    features      jsonb NOT NULL DEFAULT '{}'::jsonb,
    is_active     boolean NOT NULL DEFAULT true,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    created_by    uuid,
    updated_by    uuid
);
CREATE UNIQUE INDEX plans_code_key ON plans (lower(code));

-- --- identity ----------------------------------------------------------------

CREATE TABLE users (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    email           text NOT NULL,
    full_name       text NOT NULL,
    -- Argon2id encoded hash. Never a plaintext or reversible value.
    password_hash   text NOT NULL,
    portal          portal_type NOT NULL DEFAULT 'app',
    status          user_status NOT NULL DEFAULT 'invited',
    phone           text,
    avatar_url      text,
    last_login_at   timestamptz,
    -- Cleared on a successful login; drives lockout.
    failed_logins   integer NOT NULL DEFAULT 0,
    locked_until    timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id)
);
CREATE UNIQUE INDEX users_org_email_key ON users (organization_id, lower(email));

CREATE TABLE roles (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    code            text NOT NULL,
    name            text NOT NULL,
    description     text,
    -- Seeded per organisation and not deletable through the API.
    is_system       boolean NOT NULL DEFAULT false,
    -- {"hr": ["read","create"], "invoices": ["read"]} — read by authz.Can().
    permissions     jsonb NOT NULL DEFAULT '{}'::jsonb,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id)
);
CREATE UNIQUE INDEX roles_org_code_key ON roles (organization_id, lower(code));

CREATE TABLE user_roles (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id         uuid NOT NULL,
    role_id         uuid NOT NULL,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, user_id) REFERENCES users (organization_id, id) ON DELETE CASCADE,
    FOREIGN KEY (organization_id, role_id) REFERENCES roles (organization_id, id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX user_roles_unique ON user_roles (organization_id, user_id, role_id);

CREATE TABLE sessions (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    user_id         uuid NOT NULL,
    -- Only the hash is stored, so a database leak does not hand over live
    -- sessions. Globally unique on purpose: a collision across organisations
    -- would be worse than one within.
    token_hash      text NOT NULL,
    user_agent      text,
    ip              inet,
    expires_at      timestamptz NOT NULL,
    revoked_at      timestamptz,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    FOREIGN KEY (organization_id, user_id) REFERENCES users (organization_id, id) ON DELETE CASCADE
);
CREATE UNIQUE INDEX sessions_token_hash_key ON sessions (token_hash);
CREATE INDEX sessions_org_user_idx ON sessions (organization_id, user_id) WHERE revoked_at IS NULL;

-- --- audit -------------------------------------------------------------------

-- Partitioned by month on created_at. Audit is append-only and grows without
-- bound, so retention is a DETACH plus DROP of an old partition rather than a
-- DELETE that would rewrite the table.
--
-- A partitioned table's primary key must contain the partition key, hence
-- (id, created_at) rather than id alone.
CREATE TABLE audit_log (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid NOT NULL DEFAULT uuid_generate_v7(),
    actor_id        uuid,
    actor_label     text NOT NULL,
    action          audit_action NOT NULL,
    entity_type     text NOT NULL,
    entity_id       uuid,
    before          jsonb,
    after           jsonb,
    request_id      text,
    ip              inet,
    created_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

CREATE INDEX audit_log_org_created_idx ON audit_log (organization_id, created_at DESC);
CREATE INDEX audit_log_org_entity_idx  ON audit_log (organization_id, entity_type, entity_id);

CREATE TABLE audit_log_2026_08 PARTITION OF audit_log
    FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');
CREATE TABLE audit_log_2026_09 PARTITION OF audit_log
    FOR VALUES FROM ('2026-09-01') TO ('2026-10-01');
CREATE TABLE audit_log_2026_10 PARTITION OF audit_log
    FOR VALUES FROM ('2026-10-01') TO ('2026-11-01');
CREATE TABLE audit_log_2026_11 PARTITION OF audit_log
    FOR VALUES FROM ('2026-11-01') TO ('2026-12-01');
CREATE TABLE audit_log_2026_12 PARTITION OF audit_log
    FOR VALUES FROM ('2026-12-01') TO ('2027-01-01');

-- Catches anything outside the ranges above. Without it an insert dated beyond
-- the last partition fails outright, which would turn a missed maintenance job
-- into a write outage. Rows landing here are the signal to add partitions.
CREATE TABLE audit_log_default PARTITION OF audit_log DEFAULT;

-- --- configuration -----------------------------------------------------------

CREATE TABLE feature_flags (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    key             text NOT NULL,
    is_enabled      boolean NOT NULL DEFAULT false,
    -- Optional structured payload: variant names, limits, rollout percentages.
    value           jsonb NOT NULL DEFAULT '{}'::jsonb,
    description     text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id)
);
CREATE UNIQUE INDEX feature_flags_org_key ON feature_flags (organization_id, lower(key));

-- Gapless document numbering. GST requires invoice numbers to be sequential
-- within a financial year, so the counter lives in the database and is bumped
-- inside the same transaction that writes the document — never computed with a
-- MAX(number)+1 read, which two concurrent requests would both win.
CREATE TABLE number_series (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    kind            number_kind NOT NULL,
    -- Financial year label, e.g. '2026-27'. Series reset each year.
    fy_label        text NOT NULL,
    prefix          text NOT NULL DEFAULT '',
    suffix          text NOT NULL DEFAULT '',
    padding         smallint NOT NULL DEFAULT 4,
    next_number     bigint NOT NULL DEFAULT 1,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id),
    CONSTRAINT number_series_next_check CHECK (next_number > 0),
    CONSTRAINT number_series_padding_check CHECK (padding BETWEEN 0 AND 12)
);
CREATE UNIQUE INDEX number_series_unique ON number_series (organization_id, kind, fy_label);

CREATE TABLE settings (
    organization_id uuid NOT NULL REFERENCES organizations (id) ON DELETE CASCADE,
    id              uuid PRIMARY KEY DEFAULT uuid_generate_v7(),
    -- Dotted namespace, e.g. 'payroll.pf_rate' or 'invoice.default_terms'.
    key             text NOT NULL,
    value           jsonb NOT NULL DEFAULT '{}'::jsonb,
    description     text,
    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now(),
    created_by      uuid,
    updated_by      uuid,
    UNIQUE (organization_id, id)
);
CREATE UNIQUE INDEX settings_org_key ON settings (organization_id, lower(key));
