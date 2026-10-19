# Statement flow – eval set

Synthetic test data with known correct answers. Run each PDF through the normal Zap, then compare what lands in Supabase with the matching file in `expected/`.

## Files

| Test file | Expected answer | What it tests |
|---|---|---|
| Kontoauszug_2026-08/09/10_Musterbank.pdf (from earlier) | `Kontoauszug_2026-0X_Musterbank.expected.json` | Baseline: 45 transactions, categories, normalisation across 3 months |
| `Test_A_English_layout.pdf` | `Test_A_English_layout.expected.json` | Other bank, English labels, DD/MM/YYYY dates, English number format, amount before details, payee + description in one column |
| `Test_B_Reversals_and_duplicates.pdf` | `Test_B_Reversals_and_duplicates.expected.json` | Rücklastschrift (returned debit) and Storno (refund) flagged as reversals; two identical REWE payments on the same day both kept; messy payees ("SEPA-LASTSCHRIFT VATTENF.", "PAYPAL *NETFLIX.COM") |
| `Test_C_Not_a_statement.pdf` | `Test_C_Not_a_statement.expected.json` | Invoice must return `is_statement: false` and save nothing, even though it contains an IBAN and amounts |

Each test uses its own account (DE00, DE11, DE22), so test data never mixes.

## Scoring rules

| Check | Pass when |
|---|---|
| Statement fields | `is_statement`, `account_id`, period, opening and closing balance match exactly |
| Transaction count | Same number of transactions saved |
| Amount and date | Exact match for every transaction (matched by date + amount + payee) |
| Normalised payee | Value is in `accepted_normalised_payee` (case-insensitive) |
| Category | Value is in `accepted_category` |
| Reversal flag | `is_reversal` matches |
| Duplicates | Re-running the same file adds 0 rows |

Report per test: % correct for each check, plus a list of every mismatch.

## Gap found while building this set (fixed)

Deutschlandticket (DB Vertrieb GmbH) had no fitting category. Fixed: `transport` added to the category list; expected files updated.

## Signal evals

After all test statements are processed (so `detect_all_signals` has run for each account), check the signals:

- `expected/signals.expected.json`: the answer key, with the expected signals per test account and what must not appear.
- `signal_eval.sql`: paste into the Supabase SQL Editor and run. Part 1 compares counts per account and signal type; Part 2 spot-checks key values (Vattenfall price increase, streaming overlap, XYZ Digital, rhythms and due dates, provisional flags). Every row should say PASS.
