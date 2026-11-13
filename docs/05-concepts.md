# Learning Map — concept → where you build it → what to say in an interview

| Concept | Where it lives in PayFlow Lite | Interview one-liner |
|---|---|---|
| **4-party model** | `internal/simulator`: PG → Acquirer → Network → Issuer, each hop logged in `payment_events.hop` and shown as a timeline on the payment page | "The PG talks to the acquirer; the network routes by BIN to the issuer, who approves because it holds the customer's account." |
| **Transaction lifecycle** | Payment state machine: INITIATED → PROCESSING → AUTHORIZED → CAPTURED → SETTLED, FAILED, REVERSED | "Authorization blocks funds; capture claims them; settlement moves them to the merchant." |
| **Auth vs capture / reversal** | Merchant `capture_mode = MANUAL` → capture or void endpoints | "Hotels and e-commerce authorize first and capture on shipment; a void releases the block without money moving." |
| **Idempotency** | (1) checkout `idempotency_key` + unique index, (2) refund `Idempotency-Key`, (3) webhook `evt_` id, (4) settlement unique `(merchant, cycle_date)` | "Networks retry. Every write that can be retried needs a key so retry = same result, not a duplicate charge." |
| **Webhooks** | Outbox table written in same DB txn → worker goroutine delivers, HMAC signature, 3 retries with backoff, mock merchant de-dupes | "Outbox guarantees we never lose an event even if we crash right after committing." |
| **Signature verification** | `PayFlow-Signature` header, timestamp to stop replay attacks | "HMAC proves it came from us and wasn't modified; timestamp stops replays." |
| **Settlement T+1** | Cron job + admin trigger; captures on T settle on T+1; payments → SETTLED; UTR issued | "PGs hold funds in a nodal/escrow account and pay out on a cycle; T+1/T+2 covers risk and refunds." |
| **MDR + GST** | Settlement deducts 2% MDR + 18% GST on MDR. ₹1,000 → fee ₹20 + GST ₹3.60 → net ₹976.40 | "MDR is split between issuer (interchange), network (scheme fee) and acquirer/PG (markup)." |
| **Interchange** | Conceptual — mention how our 2% would be split | "Interchange goes to the issuer and is the biggest part of MDR." |
| **Double-entry ledger** | `ledger_entries`, every journal balances, balances computed by SUM | "Never store balance as a mutable column — derive it from an append-only ledger so it's auditable." |
| **Refunds vs chargebacks** | Refunds built (merchant-initiated, partial, multiple). Chargebacks: README section only | "Refund = merchant chooses to return money. Chargeback = customer disputes with their issuing bank; merchant must prove otherwise." |
| **Acquirer vs issuer** | Two separate structs in the simulator | "Acquirer = merchant's bank. Issuer = customer's bank (who issued the card)." |
| **PCI DSS** | We store BIN + last4 only, never CVV, never full PAN. Card number never logged | "Real PGs tokenize the card in a PCI-certified vault so merchant systems never touch raw card data." |
| **Reconciliation** (stretch) | Mock bank statement vs our settlements by UTR → MATCHED / MISMATCH / MISSING | "Every day the PG matches its records with the bank's file; mismatches become ops tickets." |
| **Money as integers** | All `*_paise BIGINT` | "Floats can't represent 0.1 exactly; money is always integer minor units." |
