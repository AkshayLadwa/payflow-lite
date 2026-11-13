# Decision Log (Architecture / Product Decision Records)

How to read: each decision = context → options → choice → **why** → **why not** the others → trade-off we accept.
In interviews, TPMs are judged on *trade-off reasoning*, not on the choice itself.

---

### D-01 · Money stored as integer paise, not decimals/floats
- **Options:** float · decimal · integer minor units (paise)
- **Choice:** integer paise (`₹10.50` = `1050`)
- **Why:** floats can't represent 0.1 exactly → rounding errors that add up across millions of transactions; integers are exact and fast.
- **Why not decimal:** works, but every layer (DB, code, JSON, frontend) must agree on precision; integers avoid that whole class of bugs.
- **Trade-off:** display layer must divide by 100. Small cost.

### D-02 · Refund is its own entity, not a payment status
- **Options:** add `REFUNDED` to payment status · separate `refunds` table
- **Choice:** separate table, many refunds per payment
- **Why:** partial refunds (₹300 of ₹1,000, then ₹200 more) can't be expressed by one status; each refund needs its own id, amount, status, idempotency key, webhook.
- **Why not status:** "PARTIALLY_REFUNDED" breaks the moment there are two partial refunds.
- **Trade-off:** "how much is refunded" is a SUM query, not a column.

### D-03 · A retry is a new payment attempt
- **Options:** let FAILED go back to PROCESSING · create a new attempt under the same payment link
- **Choice:** new attempt; FAILED is final
- **Why:** audit trail stays truthful (bank declined attempt #1, approved attempt #2); success-rate metrics stay accurate; state machine only moves forward.
- **Why not reopen:** you lose the record of the decline and can't compute "first-attempt success rate", a core PG metric.
- **Trade-off:** one link → many payments; the dashboard must group them.

### D-04 · Split authorize and capture
- **Options:** single SUCCESS state · AUTHORIZED then CAPTURED
- **Choice:** split, with merchant setting auto (default) / manual capture
- **Why:** this is how card rails really work; hotels, cabs and e-commerce authorize first and capture later; enables **void/reversal** with no money moved.
- **Why not single state:** simpler, but hides the concept every fintech interviewer asks about.
- **Trade-off:** one extra state, two extra endpoints.

### D-05 · Idempotency keys on every retryable write
- **Where:** checkout submit, refund creation, webhook event id, settlement run (unique per merchant per day)
- **Why:** networks time out and clients retry. Without keys, a retry = double charge / double refund / double payout — the most expensive bug class in payments.
- **Why not "just disable the button":** the frontend can't protect against network-level retries, mobile reconnects, or server-to-server retries.
- **Trade-off:** extra column + unique index per table.

### D-06 · Webhooks via the Outbox pattern
- **Options:** call merchant URL directly inside the request · message queue (Kafka/RabbitMQ/SQS) · outbox table + worker
- **Choice:** outbox table in Postgres, polled by a background worker
- **Why:** event is saved in the *same database transaction* as the state change → if we crash, the event is never lost and never sent for a change that didn't happen.
- **Why not direct call:** merchant server slow/down → our checkout is slow/down; and a crash between "save" and "send" loses the event.
- **Why not Kafka/SQS:** correct at scale, but extra infra, cost and ops for a 2-week MVP. Outbox is the standard stepping stone and can feed a queue later.
- **Trade-off:** polling adds a few seconds of delay; fine for webhooks.

### D-07 · Retry policy: 3 attempts, exponential backoff (now, +30s, +2m)
- **Why exponential:** gives a struggling merchant server time to recover instead of hammering it.
- **Why 3 / minutes:** spec requirement and demo-friendly. Real PGs retry over ~24h (Stripe: up to 3 days). **This is a deliberate MVP deviation — call it out.**
- **Mitigation:** manual "Redeliver" button + delivery log.

### D-08 · Signed webhooks (HMAC + timestamp)
- **Why:** merchant must be able to prove a "payment.captured" call came from us; otherwise anyone could POST a fake success and get goods for free.
- **Why timestamp:** stops replay of an old valid message.

### D-09 · Double-entry ledger; balances are computed, never stored
- **Options:** `balance` column updated in place · append-only double-entry ledger
- **Choice:** ledger (accounts: nodal account, merchant payable, fee revenue, GST payable)
- **Why:** every rupee movement is explainable and auditable; debits must equal credits, so errors are detectable; required for reconciliation and audits.
- **Why not balance column:** one bad update and the money "disappears" with no trace of why. Finance and regulators won't accept that.
- **Trade-off:** more rows, balance = SUM query (fine at our scale; real systems add snapshots).

### D-10 · T+1 settlement in IST, net of MDR + GST, re-runnable
- **Why T+1:** industry norm in India for standard merchants; the gap covers refunds, fraud checks, and bank file timings.
- **Why IST cycle:** "day T" must match the merchant's and bank's business day, not the server's UTC day.
- **Why re-runnable:** batch jobs fail midway; unique (merchant, date) means re-running can't pay twice.
- **Why admin trigger:** demo can't wait 24h — a simulated clock is a standard testing technique.

### D-11 · Store only BIN + last 4 digits of the card
- **Why:** storing full card numbers puts the system in full PCI DSS scope (audits, encryption, network segmentation). In India, RBI's card-on-file tokenization rules (2022) also bar merchants/PGs from storing card data.
- **Why not store "encrypted" full PAN:** still in scope; no business need for an MVP.
- **Trade-off:** no saved cards / recurring payments in v1.

### D-12 · Tech stack
| Decision | Choice | Why | Why not the alternative |
|---|---|---|---|
| Backend | **Go** | Widely used in Indian fintech (Razorpay, PhonePe, Juspay); strong at concurrent background work (webhook workers); single deployable file | FastAPI: faster to prototype, but less common for payment cores |
| Frontend | **Server-rendered by Go** (templates + HTMX) | One service = one deploy, fewer moving parts for a 2-week timeline | Next.js: better for rich UI, but adds a second codebase, deploy and CORS setup — not worth it for an internal-style dashboard |
| Database | **Postgres (Neon)** | Transactions + constraints are essential for money; free tier | Supabase: good, but its auth/functions would split logic outside our backend. MongoDB: weaker multi-row transactions — wrong fit for ledgers |
| Hosting | **Railway** | Always-on service, so workers and cron keep running | Render free tier sleeps after ~15 min → retries and settlement silently stop |
| Jobs | **In-process worker + cron** | No extra infra | Separate queue service: right at scale, overkill for MVP |

---

## Template for new decisions
```
### D-xx · <title>
- Context:
- Options:
- Choice:
- Why:
- Why not:
- Trade-off / risk accepted:
- Revisit when:
```
