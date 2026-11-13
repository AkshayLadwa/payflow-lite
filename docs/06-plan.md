# Build Plan — TPM track

**Roles:** You = Product Manager / TPM (owner of problem, scope, decisions, risks, acceptance, go-live).
Claude = engineering team (builds to your specs; you do UAT against your acceptance criteria).

**Rule:** every day produces an artifact you could show in an interview.

## Week 1 — Conceptualise & Design

| Day | Theme | You produce | Fintech learning |
|---|---|---|---|
| 1 | Domain immersion | One-page "How a card payment works" in your own words + competitor teardown (Razorpay Payment Links, Cashfree, Stripe) | 4-party model, acquirer vs issuer, auth/capture/settle |
| 2 | Problem & product | PRD v1: problem statement, personas, goals/non-goals, success metrics (see below) | How PGs make money (MDR, interchange) |
| 3 | Requirements | User stories + acceptance criteria, MoSCoW priority, MVP cut, in a board (GitHub Projects / Jira free) | Refunds vs chargebacks, idempotency |
| 4 | Compliance & risk | Compliance checklist + risk register (likelihood × impact, owner, mitigation) | RBI Payment Aggregator rules, PCI DSS, card tokenization, data localisation, escrow/nodal accounts |
| 5 | Design review | Walk through state machines, schema, API with Claude; challenge each decision; finalise decision log; non-functional requirements (uptime, latency, retries) | Outbox, ledger, settlement, reconciliation |

## Week 2 — Execute (2 sprints) & Launch

| Day | Theme | You do | Claude does |
|---|---|---|---|
| 6 | Sprint 1 planning + kickoff | Sprint goal, pick stories, definition of done | Setup, DB, deploy skeleton, onboarding |
| 7 | Sprint 1 | Daily standup note, UAT onboarding | Payment links, checkout, simulator, state machine |
| 8 | Sprint 1 review | UAT payments + webhooks; log bugs with severity/priority; sprint review | Webhooks, retries, signatures |
| 9 | Sprint 2 | Re-prioritise based on bugs (scope trade-offs) | Ledger, refunds, settlement + MDR |
| 10 | Sprint 2 | UAT money flows — verify ₹1,000 → ₹976.40 yourself | Dashboard, fixes |
| 11 | Launch readiness | Go-live checklist, runbook ("webhooks failing — what do we do?"), rollback plan | Production deploy, monitoring/logs |
| 12 | Launch + retro | Go/no-go call, release notes, retrospective, metrics snapshot | Hot fixes |
| 13 | Case study | Portfolio write-up: problem → decisions → trade-offs → delivery → learnings | — |
| 14 | Ship the story | Demo video (you narrate as PM), LinkedIn post | — |

## Success metrics to define in the PRD (real PG metrics)
- Payment success rate (and first-attempt success rate)
- Webhook delivery success rate within 3 attempts
- Settlement on-time rate (T+1 SLA)
- Reconciliation mismatch rate
- Time-to-first-payment for a new merchant (onboarding friction)

## Cut list if behind (in order)
Reconciliation → manual capture/void → settlement CSV → UI polish.
Never cut: idempotency, outbox/retries, ledger, settlement math — these are the interview story.

## Engineering reference (for design review, not to memorise)
`01-brd.md`, `02-state-machines.md`, `03-schema.sql`, `04-api.md`, `05-concepts.md`, `07-decision-log.md`
