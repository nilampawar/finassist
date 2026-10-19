# Gmail flow – golden dataset

12 synthetic emails (`test_emails.json`) with the correct decision for each (`test_emails.expected.json`). All senders use `.example` domains; the account holder is Anna Beispiel (account DE00****0000), processing date 7 Oct 2026.

| ID | Email | Expected type | What it tests |
|---|---|---|---|
| E01 | Vattenfall advance payment 94 → 102 from 1 Dec | price_change | Real price increase; agent checks the recurring payment |
| E02 | Audible trial ends 15 Oct, then 9.95/month | price_change | Free trial turning paid |
| E03 | Telekom bill 39.95, direct debit | upcoming_bill (no card) | Normal bill at the usual amount: list only |
| E04 | Utility top-up 186.40, transfer by 5 Nov | upcoming_bill or pending_payment (card) | Transfer needed and unusual amount |
| E05 | School trip fee 180, due Wednesday 14 Oct | pending_payment | Payment the user must make |
| E06 | Yoga workshop 45, pay by 17 Oct | pending_payment | Registration waiting for payment |
| E07 | Flight for Anna, 20 Nov – 8 Dec | travel_booking | Trip for the user; suggest pausing subscriptions |
| E08 | Flight for Max Mustermann | ignore | Booking for someone else |
| E09 | "Prices are rising, switch now!" | ignore | Marketing pretending to be a price change |
| E10 | FitX reminder, due 30 Sep | ignore or uncertain (never pending_payment) | Borderline: bank shows it was already paid (Aug–Oct, no returned debit). Pass if the agent never asks the user to pay |
| E11 | Vattenfall new payment plan: 120 from 1 Dec, no old amount mentioned | price_change | Agent must look up the current 94 to notice the increase (real MCP test) |
| E12 | Vattenfall plan 125: subject says December, body says 1 Nov | price_change or uncertain, needs_attention = true | Conflicting dates: body date wins (2026-11-01); flagging the conflict is nice to have |

**How to use:** run each email through the agent (manual trigger with the email as input), compare type, provider, amounts and dates with the answer key, and run each email 2–3 times to check the type stays the same. For a live Gmail demo, send yourself 2–3 of these (e.g. E01, E05, E07).

## Results – Haiku 5.5, final prompt (12 Oct 2026)

All 11 emails pass (E11 not sent; E12 replaces it). Regression re-run of E01–E03 after the last prompt change: all pass, E03 correctly stays without a card.
