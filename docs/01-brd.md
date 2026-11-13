# PayFlow Lite — Business Requirements (1 page)

## Problem
Merchants need a way to accept card payments online, get notified reliably when
payments succeed or fail, and receive their money in their bank account on a
predictable schedule — minus fees. PayFlow Lite **simulates** a payment gateway
(PG) end to end so the full lifecycle can be built, demoed and explained.

## Users
| Actor | What they do |
|---|---|
| Merchant | Signs up, configures bank + webhook, creates payment links, captures/voids, refunds, views dashboard |
| Customer | Opens a payment link, pays with a test card |
| PG operator (admin) | Triggers settlement / reconciliation runs (simulated clock for demos) |
| Simulated parties | Acquiring bank, card network (Visa/Mastercard), issuing bank — inside our code |

## In scope (one line per feature)
1. **Onboarding** — email/password signup, business name + type, mock bank (account no. + IFSC), webhook URL, API key.
2. **Payment links** — merchant creates link (amount, description, customer email) → `/pay/{slug}`.
3. **Checkout** — customer enters test card; card passes through simulated Acquirer → Network → Issuer.
4. **Payment state machine** — `INITIATED → PROCESSING → AUTHORIZED → CAPTURED → SETTLED`, or `FAILED` / `REVERSED`. Every transition logged.
5. **Auth vs capture** — merchant setting: auto-capture (default) or manual capture/void.
6. **Webhooks** — outbox pattern, HMAC-signed, unique event id (idempotency), 3 attempts with exponential backoff, delivery log, manual redeliver.
7. **Settlement T+1** — payments captured on day T settle on T+1; MDR 2% + 18% GST deducted; settlement report with mock UTR.
8. **Refunds** — full or partial, multiple per payment, never exceeding captured amount; deducted from next settlement.
9. **Ledger** — double-entry, append-only; balances are computed, never stored.
10. **Dashboard** — transactions (filter status/date), revenue summary, settlements, refunds, webhook logs.
11. **Reconciliation (stretch)** — compare our settlement records with a mock bank statement; flag mismatches.

## Out of scope (non-goals)
Real money, real cards, real banks, PCI compliance, KYC, multi-currency (INR only),
chargebacks (explained in docs only), UPI/netbanking, multi-user merchant teams, email sending.

## Business rules
- Money is stored as **integer paise** (`₹10.50` = `1050`). Never floats.
- We store only card **BIN (first 6) + last 4**. Never the full number, never CVV.
- A payment link can have many payment **attempts**; a failed attempt never changes again — a retry is a new attempt. Link becomes `PAID` on first successful capture.
- `sum(processed refunds) ≤ captured amount`.
- MDR = 2% of gross; GST = 18% of MDR. Net = gross − MDR − GST − refunds.
- Settlement cycle T = calendar day in IST (Asia/Kolkata).
- Webhook retries: attempt 1 immediate, attempt 2 after 30s, attempt 3 after 2m (demo-friendly; real PGs retry over ~24h).

## Success criteria (Day 14)
- Live URL: a stranger can sign up, create a link, pay with `4242…`, see the webhook arrive, run settlement, and see net payout with fees.
- README explains every concept in `05-concepts.md` with a pointer to the code.
- 3–5 min demo video.
