CREATE OR REPLACE FUNCTION public.detect_unknown_debits(p_account text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare
  v_months int;
  v_latest date;
  v_first_month date;                                   -- NEW
  v_run timestamptz := clock_timestamp();
  v_count int := 0;
begin
  select count(distinct m), max(s.period_end), min(date_trunc('month', s.period_start))::date   -- NEW (third value)
    into v_months, v_latest, v_first_month
  from statements s,
       generate_series(date_trunc('month', s.period_start),
                       date_trunc('month', s.period_end),
                       interval '1 month') as m
  where s.account_id = p_account;

  if coalesce(v_months, 0) >= 2 then
    with first_seen as (
      select t.normalised_payee as payee, min(t.date) as first_date
      from transactions t
      join statements s on s.id = t.statement_id
      where s.account_id = p_account
        and t.amount < 0
        and not t.is_reversal
        and t.normalised_payee is not null
      group by t.normalised_payee
    ),
    found as (
      select t.normalised_payee as payee, fs.first_date,
             sum(abs(t.amount)) as amt,
             count(*) as n,
             (array_agg(t.category))[1] as cat,
             (array_agg(t.payee))[1] as raw_payee,
             (array_agg(t.description))[1] as description
      from transactions t
      join statements s on s.id = t.statement_id
      join first_seen fs on fs.payee = t.normalised_payee
      join category_groups g on g.category = t.category
      where s.account_id = p_account
        and t.amount < 0
        and not t.is_reversal
        and g.group_name in ('subscription', 'other')
        and t.category not in ('transfer', 'interest')
        and t.date = fs.first_date
        and v_latest - fs.first_date <= 60
        and date_trunc('month', fs.first_date)::date > v_first_month   -- NEW: not in the baseline month
      group by t.normalised_payee, fs.first_date
    )
    insert into signals (signal_key, account_id, signal_type, normalised_payee, category,
                         amount, monthly_impact, confidence, is_provisional, rank_score,
                         details, status, detected_at, updated_at)
    select p_account || '|unknown_debit|' || payee || '|' || first_date, p_account,
           'unknown_debit', payee, cat,
           amt, amt,
           case when v_months >= 3 then 0.9 else 0.7 end,
           false,
           round(amt * case when v_months >= 3 then 0.9 else 0.7 end, 2),
           jsonb_build_object('first_date', first_date, 'raw_payee', raw_payee,
                              'description', description, 'payment_count', n),
           'new', v_run, v_run
    from found
    on conflict (signal_key) do update set
      category       = excluded.category,
      amount         = excluded.amount,
      monthly_impact = excluded.monthly_impact,
      confidence     = excluded.confidence,
      rank_score     = excluded.rank_score,
      details        = excluded.details,
      status         = case when signals.status = 'withdrawn' then 'new' else signals.status end,
      updated_at     = excluded.updated_at;

    get diagnostics v_count = row_count;
  end if;

  update signals
     set status = 'withdrawn', updated_at = v_run
   where account_id = p_account
     and signal_type = 'unknown_debit'
     and status in ('new', 'shown')
     and updated_at < v_run;

  return v_count;
end;
$function$;
