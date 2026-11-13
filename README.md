# PayFlow Lite

A payment gateway simulator: merchants create payment links, customers pay with
test cards that flow through a simulated acquirer → card network → issuer, merchants
receive signed webhooks, and money settles T+1 (minus MDR + GST) via a double-entry ledger.

No real money, cards or banks.

## Stack
| Layer | Choice |
|---|---|
| Language | Go 1.25 (one language for everything) |
| HTTP | standard library `net/http` (Go 1.22+ routing) |
| UI | Go `html/template` + HTMX + Pico.css (server-rendered, no JS build) |
| DB | PostgreSQL on Neon, driver `pgx/v5`, migrations with `goose` |
| Jobs | in-process worker goroutine (webhooks) + `robfig/cron/v3` (settlement) |
| Deploy | Railway — single service |

## Docs
1. [Business requirements](docs/01-brd.md)
2. [State machines](docs/02-state-machines.md)
3. [Database schema](docs/03-schema.sql)
4. [API & pages](docs/04-api.md)
5. [Learning map](docs/05-concepts.md)
6. [Build plan — TPM track](docs/06-plan.md)
7. [Decision log — why this, why not that](docs/07-decision-log.md)
