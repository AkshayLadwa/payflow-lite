# API & Pages

Three kinds of auth:
- **Session cookie** — merchant dashboard (HTML pages).
- **API key** — `Authorization: Bearer pk_test_…` — server-to-server `/v1` API.
- **Public** — checkout page.

## Merchant dashboard (HTML, session cookie)
| Method | Path | Purpose |
|---|---|---|
| GET/POST | `/signup` | Create merchant |
| GET/POST | `/login`, POST `/logout` | Session |
| GET | `/dashboard` | Revenue summary (today, 7d, pending settlement, settled) |
| GET/POST | `/settings` | Business info, bank details, webhook URL, capture mode, show webhook secret |
| POST | `/settings/api-keys` | Generate key (shown once) |
| GET/POST | `/links` | List / create payment links |
| GET | `/payments?status=&from=&to=` | Transactions list |
| GET | `/payments/{id}` | Detail: 4-party hop timeline, refunds, webhook events |
| POST | `/payments/{id}/capture` · `/void` · `/refunds` | Same as API, from the UI |
| GET | `/settlements`, `/settlements/{id}` | Settlement history + report (CSV download) |
| GET | `/webhooks` | Event log + delivery attempts |
| POST | `/webhooks/{eventId}/redeliver` | Manual retry |

## Merchant API (`/v1`, API key, JSON)
| Method | Path | Notes |
|---|---|---|
| POST | `/v1/payment_links` | `{amount_paise, description, customer_email}` → `{id, url}` |
| GET | `/v1/payment_links/{id}` | |
| GET | `/v1/payments` | `?status=&from=&to=` |
| GET | `/v1/payments/{id}` | |
| POST | `/v1/payments/{id}/capture` | AUTHORIZED → CAPTURED |
| POST | `/v1/payments/{id}/void` | AUTHORIZED → REVERSED |
| POST | `/v1/payments/{id}/refunds` | `{amount_paise, reason}` + `Idempotency-Key` header |

## Public checkout
| Method | Path | Notes |
|---|---|---|
| GET | `/pay/{slug}` | Checkout page |
| POST | `/pay/{slug}/attempts` | Card form submit. Hidden `idempotency_key` generated when page loads → double-submit returns same payment |
| GET | `/pay/{slug}/status/{paymentId}` | Result page (polls until terminal state) |

## Admin / simulator (protected by `ADMIN_TOKEN` env var)
| Method | Path | Notes |
|---|---|---|
| POST | `/admin/settlements/run?cycle_date=2026-11-13` | Run T+1 settlement now (for demo) |
| POST | `/admin/recon/run?date=…&inject_mismatch=true` | Stretch |

## Mock merchant (to demo webhooks)
| Method | Path | Notes |
|---|---|---|
| POST | `/mock-merchant/webhook?fail=true` | Verifies signature, de-duplicates by event id, optionally returns 500 to show retries |

## Webhook format
```http
POST <merchant webhook_url>
Content-Type: application/json
PayFlow-Signature: t=1763020800,v1=<hex HMAC-SHA256(webhook_secret, "1763020800." + body)>

{
  "id": "evt_01JC…",            // idempotency key — same on every retry
  "type": "payment.captured",
  "created_at": "2026-11-13T10:15:00Z",
  "data": { "payment_id": "…", "amount_paise": 100000, "status": "CAPTURED", "payment_link_id": "…" }
}
```
Retries: attempt 1 now, 2 after 30s, 3 after 2m (`30s × 4^(n-2)`). Any 2xx within 10s = delivered.

## Error format (all JSON endpoints)
```json
{ "error": { "code": "refund_exceeds_amount", "message": "Refund of ₹600 exceeds refundable ₹500" } }
```
