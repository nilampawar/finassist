CREATE OR REPLACE FUNCTION public.detect_recurring_payments(p_account text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$declare
  v_months int;
  v_latest date;
  v_run timestamptz := clock_timestamp();
  v_count int;
begin
  -- How many months of data does this account have, and up to when?
  select count(distinct m), max(s.period_end)
    into v_months, v_latest
  from statements s,
       generate_series(date_trunc('month', s.period_start),
                       date_trunc('month', s.period_end),
                       interval '1 month') as m
  where s.account_id = p_account;

  if coalesce(v_months, 0) = 0 then
    return 0;
  end if;

  -- Find recurring payees and save them as signals
  with pay as (
    select t.normalised_payee as payee, t.category, t.date, abs(t.amount) as amt,
           t.date - lag(t.date) over (partition by t.normalised_payee order by t.date) as gap
    from transactions t
    join statements s on s.id = t.statement_id
    join category_groups g on g.category = t.category
    where s.account_id = p_account
      and t.amount < 0
      and not t.is_reversal
      and t.normalised_payee is not null
      and g.group_name in ('fixed_cost', 'subscription')
  ),
  agg as (
    select payee,
           count(*) as n,
           count(distinct date_trunc('month', date)) as months_seen,
           max(date) as last_date,
           bool_and(gap is null or gap between 25 and 35) as regular,
           (array_agg(amt order by date desc))[1] as last_amt,
           (array_agg(category order by date desc))[1] as cat,
           jsonb_agg(jsonb_build_object('date', date, 'amount', amt) order by date) as evidence
    from pay
    group by payee
  ),
  found as (
    select *,
           case when v_months = 1 then 0.6
                when not regular then 0.5
                when n >= 3 then 0.9
                else 0.7 end as conf
    from agg
    where v_months = 1
       or (months_seen >= 2 and v_latest - last_date <= 45)
  )
  insert into signals (signal_key, account_id, signal_type, normalised_payee, category,
                       amount, monthly_impact, confidence, is_provisional, rank_score,
                       details, status, detected_at, updated_at)
  select p_account || '|recurring_payment|' || payee, p_account, 'recurring_payment',
         payee, cat, last_amt, last_amt, conf, (v_months = 1),
         round(last_amt * conf, 2),
         jsonb_build_object('payments', evidence, 'payment_count', n,
                            'months_seen', months_seen, 'months_covered', v_months),
         'new', v_run, v_run
  from found
  on conflict (signal_key) do update set
    category       = excluded.category,
    amount         = excluded.amount,
    monthly_impact = excluded.monthly_impact,
    confidence     = excluded.confidence,
    is_provisional = excluded.is_provisional,
    rank_score     = excluded.rank_score,
    details        = excluded.details,
    status         = case when signals.status = 'withdrawn' then 'new' else signals.status end,
    updated_at     = excluded.updated_at;

  get diagnostics v_count = row_count;

  -- Withdraw signals that no longer qualify
  update signals
     set status = 'withdrawn', updated_at = v_run
   where account_id = p_account
     and signal_type = 'recurring_payment'
     and status in ('new', 'shown')
     and updated_at < v_run;

  return v_count;
end;$function$;
