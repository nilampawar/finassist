-- Signal eval: run in Supabase SQL Editor after all test statements are processed.
-- Part 1 compares the number of active signals per account and type with the expected counts.
with expected(account_id, signal_type, expected_count) as (values
  ('DE00****0000', 'regular_income', 1), ('DE00****0000', 'recurring_payment', 8),
  ('DE00****0000', 'duplicate_subscription', 1), ('DE00****0000', 'price_increase', 1),
  ('DE00****0000', 'unknown_debit', 1), ('DE00****0000', 'irregular_large_debit', 2),
  ('DE00****0000', 'spending_increase', 0),
  ('DE11****0011', 'regular_income', 1), ('DE11****0011', 'recurring_payment', 4),
  ('DE11****0011', 'duplicate_subscription', 0), ('DE11****0011', 'price_increase', 0),
  ('DE11****0011', 'unknown_debit', 0), ('DE11****0011', 'irregular_large_debit', 1),
  ('DE11****0011', 'spending_increase', 0),
  ('DE22****4422', 'regular_income', 1), ('DE22****4422', 'recurring_payment', 3),
  ('DE22****4422', 'duplicate_subscription', 0), ('DE22****4422', 'price_increase', 0),
  ('DE22****4422', 'unknown_debit', 0), ('DE22****4422', 'irregular_large_debit', 0),
  ('DE22****4422', 'spending_increase', 0)
),
actual as (
  select account_id, signal_type, count(*) as actual_count
  from signals
  where status <> 'withdrawn'
    and account_id in ('DE00****0000', 'DE11****0011', 'DE22****4422')
  group by account_id, signal_type
)
select e.account_id, e.signal_type, e.expected_count,
       coalesce(a.actual_count, 0) as actual_count,
       case when e.expected_count = coalesce(a.actual_count, 0) then 'PASS' else 'FAIL' end as result
from expected e
left join actual a on a.account_id = e.account_id and a.signal_type = e.signal_type
order by result, e.account_id, e.signal_type;

-- Part 2: spot checks on key values (each row should say PASS).
select 'Vattenfall price 78 -> 94' as check_name,
       case when exists (select 1 from signals where account_id = 'DE00****0000'
         and signal_type = 'price_increase' and normalised_payee ilike '%vattenfall%'
         and previous_amount = 78 and amount = 94 and monthly_impact = 16) then 'PASS' else 'FAIL' end as result
union all
select 'Streaming overlap 23.98, saving 9.99',
       case when exists (select 1 from signals where account_id = 'DE00****0000'
         and signal_type = 'duplicate_subscription' and category = 'streaming'
         and amount = 23.98 and monthly_impact = 9.99) then 'PASS' else 'FAIL' end
union all
select 'XYZ Digital unknown debit 29.90',
       case when exists (select 1 from signals where account_id = 'DE00****0000'
         and signal_type = 'unknown_debit' and normalised_payee ilike '%xyz%' and amount = 29.90)
         then 'PASS' else 'FAIL' end
union all
select 'HUK yearly, next 2027-09-20',
       case when exists (select 1 from signals where account_id = 'DE00****0000'
         and signal_type = 'irregular_large_debit' and category = 'insurance'
         and details->>'rhythm' = 'yearly' and details->>'next_due_date' = '2027-09-20')
         then 'PASS' else 'FAIL' end
union all
select 'Broadcasting fee quarterly, next 2026-11-15',
       case when exists (select 1 from signals where account_id = 'DE00****0000'
         and signal_type = 'irregular_large_debit' and category = 'broadcasting_fee'
         and details->>'rhythm' = 'quarterly' and details->>'next_due_date' = '2026-11-15')
         then 'PASS' else 'FAIL' end
union all
select 'Lufthansa one-off 312.40 (Test A)',
       case when exists (select 1 from signals where account_id = 'DE11****0011'
         and signal_type = 'irregular_large_debit' and normalised_payee ilike '%lufthansa%'
         and amount = 312.40 and details->>'rhythm' = 'one_off') then 'PASS' else 'FAIL' end
union all
select 'No variable spending as recurring (REWE, Lidl, dm, Lieferando)',
       case when not exists (select 1 from signals s join category_groups g on g.category = s.category
         where s.signal_type = 'recurring_payment' and s.status <> 'withdrawn'
         and g.group_name = 'variable_spending') then 'PASS' else 'FAIL' end
union all
select 'One-month accounts are provisional',
       case when not exists (select 1 from signals where account_id in ('DE11****0011', 'DE22****4422')
         and status <> 'withdrawn' and is_provisional = false) then 'PASS' else 'FAIL' end
union all
select 'Amazon (refunded) not in any signal',
       case when not exists (select 1 from signals where normalised_payee ilike '%amazon%'
         and status <> 'withdrawn') then 'PASS' else 'FAIL' end;
