-- PayFlow Lite — PostgreSQL schema (will become migrations/0001_init.sql)
-- All money = BIGINT paise. All times = TIMESTAMPTZ (UTC); cycle dates computed in IST.

CREATE EXTENSION IF NOT EXISTS pgcrypto; -- gen_random_uuid()

-- ───────────── Merchants & auth ─────────────
CREATE TABLE merchants (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email               TEXT NOT NULL UNIQUE,
    password_hash       TEXT NOT NULL,                       -- bcrypt
    business_name       TEXT NOT NULL,
    business_type       TEXT NOT NULL,                       -- e.g. 'ecommerce','education','services'
    bank_account_number TEXT,
    bank_ifsc           TEXT,
    webhook_url         TEXT,
    webhook_secret      TEXT NOT NULL,                       -- used for HMAC signatures
    capture_mode        TEXT NOT NULL DEFAULT 'AUTO' CHECK (capture_mode IN ('AUTO','MANUAL')),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE sessions (                                      -- dashboard login (cookie holds id)
    id          TEXT PRIMARY KEY,                            -- random 32 bytes, base64
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    expires_at  TIMESTAMPTZ NOT NULL
);

CREATE TABLE api_keys (                                      -- for /v1 server-to-server API
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id UUID NOT NULL REFERENCES merchants(id) ON DELETE CASCADE,
    key_prefix  TEXT NOT NULL,                               -- 'pk_test_ab12' shown in UI
    key_hash    TEXT NOT NULL UNIQUE,                        -- sha256 of full key; full key shown once
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    revoked_at  TIMESTAMPTZ
);

-- ───────────── Payment links & payments ─────────────
CREATE TABLE payment_links (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id    UUID NOT NULL REFERENCES merchants(id),
    slug           TEXT NOT NULL UNIQUE,                     -- /pay/{slug}
    amount_paise   BIGINT NOT NULL CHECK (amount_paise > 0),
    currency       TEXT NOT NULL DEFAULT 'INR',
    description    TEXT NOT NULL,
    customer_email TEXT NOT NULL,
    status         TEXT NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE','PAID','EXPIRED')),
    expires_at     TIMESTAMPTZ NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE payments (                                      -- one row per card attempt
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_link_id  UUID NOT NULL REFERENCES payment_links(id),
    merchant_id      UUID NOT NULL REFERENCES merchants(id),
    amount_paise     BIGINT NOT NULL CHECK (amount_paise > 0),
    currency         TEXT NOT NULL DEFAULT 'INR',
    status           TEXT NOT NULL CHECK (status IN
                       ('INITIATED','PROCESSING','AUTHORIZED','CAPTURED','SETTLED','FAILED','REVERSED')),
    card_network     TEXT,                                   -- 'VISA' | 'MASTERCARD'
    card_bin         TEXT,                                   -- first 6 digits only
    card_last4       TEXT,                                   -- PCI: never store full PAN or CVV
    failure_code     TEXT,
    idempotency_key  TEXT NOT NULL,                          -- from checkout's Idempotency-Key header
    authorized_at    TIMESTAMPTZ,
    captured_at      TIMESTAMPTZ,
    settlement_id    UUID,                                   -- set when SETTLED
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (payment_link_id, idempotency_key)                -- double-click = same payment
);
CREATE INDEX payments_merchant_created_idx ON payments (merchant_id, created_at DESC);
CREATE INDEX payments_merchant_status_idx  ON payments (merchant_id, status);

CREATE TABLE payment_events (                                -- audit log of every transition / hop
    id          BIGSERIAL PRIMARY KEY,
    payment_id  UUID NOT NULL REFERENCES payments(id),
    from_status TEXT,
    to_status   TEXT NOT NULL,
    hop         TEXT,                                        -- 'PG','ACQUIRER','NETWORK','ISSUER','MERCHANT','SYSTEM'
    note        TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX payment_events_payment_idx ON payment_events (payment_id, id);

-- ───────────── Refunds ─────────────
CREATE TABLE refunds (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    payment_id      UUID NOT NULL REFERENCES payments(id),
    merchant_id     UUID NOT NULL REFERENCES merchants(id),
    amount_paise    BIGINT NOT NULL CHECK (amount_paise > 0),
    status          TEXT NOT NULL CHECK (status IN ('INITIATED','PROCESSED','FAILED')),
    reason          TEXT,
    failure_code    TEXT,
    idempotency_key TEXT NOT NULL,
    settlement_id   UUID,                                    -- which settlement deducted it
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at    TIMESTAMPTZ,
    UNIQUE (merchant_id, idempotency_key)
);

-- ───────────── Settlements ─────────────
CREATE TABLE settlements (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    merchant_id   UUID NOT NULL REFERENCES merchants(id),
    cycle_date    DATE NOT NULL,                             -- day T (IST) whose captures are settled
    payout_date   DATE NOT NULL,                             -- T+1
    gross_paise   BIGINT NOT NULL,
    refunds_paise BIGINT NOT NULL,
    mdr_paise     BIGINT NOT NULL,                           -- 2% of gross
    gst_paise     BIGINT NOT NULL,                           -- 18% of MDR
    net_paise     BIGINT NOT NULL,                           -- gross - refunds - mdr - gst
    payment_count INT NOT NULL,
    status        TEXT NOT NULL CHECK (status IN ('PENDING','PROCESSED')),
    utr           TEXT UNIQUE,                               -- mock bank reference number
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (merchant_id, cycle_date)                         -- job is safe to re-run
);

ALTER TABLE payments ADD FOREIGN KEY (settlement_id) REFERENCES settlements(id);
ALTER TABLE refunds  ADD FOREIGN KEY (settlement_id) REFERENCES settlements(id);

-- ───────────── Double-entry ledger (append-only) ─────────────
-- Accounts:
--   nodal_account           asset      money PG holds in its escrow/nodal bank account
--   merchant_payable        liability  what PG owes the merchant (per merchant)
--   pg_fee_revenue          income     MDR earned
--   gst_payable             liability  GST owed to government
-- Capture:    DR nodal_account            / CR merchant_payable   (gross)
-- Refund:     DR merchant_payable         / CR nodal_account      (refund)
-- Settlement: DR merchant_payable (gross-refunds) / CR nodal_account (net), CR pg_fee_revenue (mdr), CR gst_payable (gst)
CREATE TABLE ledger_entries (
    id           BIGSERIAL PRIMARY KEY,
    journal_id   UUID NOT NULL,                              -- entries in one journal must balance
    account      TEXT NOT NULL CHECK (account IN
                   ('nodal_account','merchant_payable','pg_fee_revenue','gst_payable')),
    merchant_id  UUID REFERENCES merchants(id),
    debit_paise  BIGINT NOT NULL DEFAULT 0 CHECK (debit_paise  >= 0),
    credit_paise BIGINT NOT NULL DEFAULT 0 CHECK (credit_paise >= 0),
    ref_type     TEXT NOT NULL,                              -- 'payment' | 'refund' | 'settlement'
    ref_id       UUID NOT NULL,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    CHECK ((debit_paise = 0) <> (credit_paise = 0))          -- exactly one side
);
CREATE INDEX ledger_merchant_account_idx ON ledger_entries (merchant_id, account);
-- Invariant check (should always return 0 rows):
--   SELECT journal_id FROM ledger_entries GROUP BY journal_id HAVING sum(debit_paise) <> sum(credit_paise);

-- ───────────── Webhooks (outbox) ─────────────
CREATE TABLE webhook_events (
    id              TEXT PRIMARY KEY,                        -- 'evt_…' = idempotency key for merchant
    merchant_id     UUID NOT NULL REFERENCES merchants(id),
    event_type      TEXT NOT NULL,                           -- 'payment.captured', 'refund.processed', …
    payload         JSONB NOT NULL,
    status          TEXT NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING','DELIVERED','FAILED')),
    attempts        INT NOT NULL DEFAULT 0,
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX webhook_events_due_idx ON webhook_events (next_attempt_at) WHERE status = 'PENDING';

CREATE TABLE webhook_deliveries (                            -- one row per HTTP attempt
    id            BIGSERIAL PRIMARY KEY,
    event_id      TEXT NOT NULL REFERENCES webhook_events(id),
    attempt_no    INT NOT NULL,
    url           TEXT NOT NULL,
    response_code INT,
    response_body TEXT,                                      -- truncated to 1 KB
    error         TEXT,
    duration_ms   INT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ───────────── Reconciliation (stretch) ─────────────
CREATE TABLE bank_statement_lines (                          -- pretend file from the bank
    id           BIGSERIAL PRIMARY KEY,
    utr          TEXT NOT NULL,
    amount_paise BIGINT NOT NULL,
    credited_on  DATE NOT NULL
);

CREATE TABLE recon_results (
    id            BIGSERIAL PRIMARY KEY,
    run_date      DATE NOT NULL,
    settlement_id UUID REFERENCES settlements(id),
    utr           TEXT,
    status        TEXT NOT NULL CHECK (status IN ('MATCHED','AMOUNT_MISMATCH','MISSING_IN_BANK','MISSING_IN_PG')),
    expected      BIGINT,
    actual        BIGINT,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
