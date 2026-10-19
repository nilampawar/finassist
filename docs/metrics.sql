-- FinAssist – product and quality metrics
-- Run in the Supabase SQL Editor. Demo users only (eval accounts excluded).

-- 1) ACTION RATE (north star): share of attention cards the user acted on
--    acted = marked done or chose an option
with cards as (
  select a.id as action_id, a.account_id
  from actions a
  join accounts ac on ac.account_id = a.account_id
  where ac.user_id is not null
),
acted as (
  select distinct action_id from feedback
  where value = 'done' or value like 'chose:%'
)
select count(*) as cards,
       count(acted.action_id) as acted_on,
       round(100.0 * count(acted.action_id) / nullif(count(*), 0), 1) as action_rate_pct
from cards left join acted using (action_id);

-- 2) USEFULNESS: helpful vs not helpful vs not relevant (per element)
select element,
       count(*) filter (where value = 'helpful')      as helpful,
       count(*) filter (where value = 'not_helpful')  as not_helpful,
       count(*) filter (where value = 'not_relevant') as not_relevant,
       round(100.0 * count(*) filter (where value = 'helpful')
             / nullif(count(*) filter (where value in ('helpful','not_helpful')), 0), 1) as helpful_pct
from feedback
group by element
order by element;

-- 3) WHICH OPTION DO PEOPLE CHOOSE vs what the agent recommended
select a.recommended,
       substring(f.value from 'chose:(.*)') as chosen,
       count(*) as times
from feedback f
join actions a on a.id = f.action_id
where f.value like 'chose:%'
group by 1, 2
order by times desc;

-- 4) AGENT QUALITY: research, calculator use, hallucination guard
select count(*)                                                         as actions,
       round(avg((extras->'meta'->>'searches')::int), 2)                as avg_searches,
       round(100.0 * count(*) filter (where (extras->'meta'->>'calculator_calls')::int > 0)
             / nullif(count(*), 0), 1)                                  as used_calculator_pct,
       sum((extras->'meta'->>'links_proposed')::int)                    as links_proposed,
       sum((extras->'meta'->>'links_dropped')::int)                     as links_dropped_by_code
from actions;

-- 5) EMAIL ADDRESSES in drafts: verified against the agent's sources vs replaced by code
select count(*) filter (where (d->>'to_verified')::boolean)       as verified,
       count(*) filter (where (d->>'to_verified')::boolean = false) as replaced_by_provider_name
from actions, jsonb_array_elements(coalesce(drafts, '[]'::jsonb)) d;

-- 6) GMAIL AGENT: what share of emails became a card, and why others did not
select email_type,
       count(*)                                    as emails,
       count(*) filter (where needs_attention)     as needed_attention,
       count(*) filter (where reason is not null)  as changed_by_code_rule
from processed_emails
group by email_type
order by emails desc;

-- 7) RELIABILITY: statement uploads that failed, by reason
select coalesce(failure_reason, '(ok)') as reason, status, count(*)
from uploads
group by 1, 2
order by 3 desc;

-- 8) CATEGORY FIT: share of transactions the AI could only put in "other"
select round(100.0 * count(*) filter (where t.category = 'other') / nullif(count(*), 0), 1) as other_pct,
       count(*) filter (where t.category = 'other') as other_count,
       count(*) as all_transactions
from transactions t
join statements s on s.id = t.statement_id
join accounts a on a.account_id = s.account_id
where a.user_id is not null;

-- 9) EMAIL-BANK MATCH: do email signals link to the user's regular bank payment of the same provider?
--    An empty matching_bank_payment on a price change or bill = names did not line up (see README, F1).
select e.signal_type, e.normalised_payee as email_name,
       r.normalised_payee as matching_bank_payment,
       e.previous_amount, r.amount as bank_amount
from signals e
left join signals r
  on r.account_id = e.account_id
 and r.signal_type = 'recurring_payment'
 and r.status <> 'withdrawn'
 and lower(r.normalised_payee) = lower(e.normalised_payee)
where e.details->>'source' = 'email'
  and e.status <> 'withdrawn'
order by e.account_id, e.signal_type;
