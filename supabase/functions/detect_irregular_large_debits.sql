CREATE OR REPLACE FUNCTION public.detect_irregular_large_debits(p_account text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare
  v_months int;
  v_latest date;
  v_run timestamptz := clock_timestamp();
  v_count int;
begin
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
      and (g.group_name = 'fixed_cost' or t.category = 'travel')
      and not exists (
        select 1 from signals r
        where r.account_id = p_account
          and r.signal_type = 'recurring_payment'
          and r.status <> 'withdrawn'
          and r.normalised_payee = t.normalised_payee)
  ),
  agg as (
    select payee,
           count(*) as n,
           max(date) as last_date,
           (array_agg(amt order by date desc))[1] as last_amt,
           (array_agg(category order by date desc))[1] as cat,
           bool_and(gap is null or gap between 80 and 100) as quarterly_gaps,
           bool_and(gap is null or gap between 350 and 380) as yearly_gaps,
           jsonb_agg(jsonb_build_object('date', date, 'amount', amt) order by date) as evidence
    from pay
    group by payee
  ),
  classified as (
    select *,
           case
             when n >= 2 and quarterly_gaps and last_amt >= 50 then 'quarterly'
             when n >= 2 and yearly_gaps and last_amt >= 50 then 'yearly'
             when n = 1 and cat = 'broadcasting_fee' and last_amt >= 50 then 'quarterly'
             when n = 1 and cat = 'insurance' and last_amt >= 50 then 'yearly'
             when n = 1 and last_amt >= 200 and v_latest - last_date <= 60 then 'one_off'
           end as rhythm
    from agg
  ),
  found as (
    select *,
           case when rhythm = 'one_off' then (v_months = 1)
                else n = 1 end as prov,
           case when rhythm = 'one_off' then (case when v_months = 1 then 0.6 else 0.9 end)
                when n = 1 then 0.6
                when n >= 3 then 0.9
                else 0.7 end as conf,
           (case rhythm when 'quarterly' then last_date + interval '3 months'
                        when 'yearly' then last_date + interval '1 year' end)::date as next_due,
           round(last_amt / case rhythm when 'quarterly' then 3 else 12 end, 2) as set_aside
    from classified
    where rhythm is not null
  )
  insert into signals (signal_key, account_id, signal_type, normalised_payee, category,
                       amount, monthly_impact, confidence, is_provisional, rank_score,
                       details, status, detected_at, updated_at)
  select p_account || '|irregular_large_debit|' || payee, p_account,
         'irregular_large_debit', payee, cat,
         last_amt, set_aside, conf, prov, round(set_aside * conf, 2),
         jsonb_build_object('rhythm', rhythm, 'next_due_date', next_due,
                            'set_aside_per_month', set_aside, 'last_date', last_date,
                            'payments', evidence),
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

  update signals
     set status = 'withdrawn', updated_at = v_run
   where account_id = p_account
     and signal_type = 'irregular_large_debit'
     and status in ('new', 'shown')
     and updated_at < v_run;

  return v_count;
end;
$function$;
