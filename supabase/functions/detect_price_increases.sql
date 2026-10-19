CREATE OR REPLACE FUNCTION public.detect_price_increases(p_account text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare
  v_run timestamptz := clock_timestamp();
  v_count int;
begin
  with rec as (
    select normalised_payee, category, confidence
    from signals
    where account_id = p_account
      and signal_type = 'recurring_payment'
      and status <> 'withdrawn'
      and not is_provisional
  ),
  pay as (
    select t.normalised_payee as payee, t.date, abs(t.amount) as amt,
           row_number() over (partition by t.normalised_payee order by t.date desc) as rn
    from transactions t
    join statements s on s.id = t.statement_id
    join rec r on r.normalised_payee = t.normalised_payee
    where s.account_id = p_account
      and t.amount < 0
      and not t.is_reversal
  ),
  latest as (
    select payee, amt as new_amt, date as new_date
    from pay where rn = 1
  ),
  base as (
    select payee,
           (percentile_cont(0.5) within group (order by amt))::numeric as old_amt
    from pay where rn > 1
    group by payee
  ),
  found as (
    select l.payee, r.category, r.confidence, l.new_amt, l.new_date,
           round(b.old_amt, 2) as old_amt,
           round(l.new_amt - b.old_amt, 2) as diff,
           round((l.new_amt - b.old_amt) / b.old_amt * 100, 1) as pct
    from latest l
    join base b on b.payee = l.payee
    join rec r on r.normalised_payee = l.payee
    where l.new_amt > b.old_amt * 1.05
      and l.new_amt - b.old_amt >= 1
  )
  insert into signals (signal_key, account_id, signal_type, normalised_payee, category,
                       amount, previous_amount, monthly_impact, confidence, is_provisional,
                       rank_score, details, status, detected_at, updated_at)
  select p_account || '|price_increase|' || payee || '|' || new_amt, p_account,
         'price_increase', payee, category,
         new_amt, old_amt, diff, confidence, false,
         round(diff * confidence, 2),
         jsonb_build_object('increase_percent', pct, 'annual_impact', diff * 12,
                            'effective_date', new_date),
         'new', v_run, v_run
  from found
  on conflict (signal_key) do update set
    previous_amount = excluded.previous_amount,
    monthly_impact  = excluded.monthly_impact,
    confidence      = excluded.confidence,
    rank_score      = excluded.rank_score,
    details         = excluded.details,
    status          = case when signals.status = 'withdrawn' then 'new' else signals.status end,
    updated_at      = excluded.updated_at;

  get diagnostics v_count = row_count;

  update signals
     set status = 'withdrawn', updated_at = v_run
   where account_id = p_account
     and signal_type = 'price_increase'
     and status in ('new', 'shown')
     and updated_at < v_run;

  return v_count;
end;
$function$;
