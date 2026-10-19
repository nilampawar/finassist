CREATE OR REPLACE FUNCTION public.detect_spending_increases(p_account text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
declare
  v_run timestamptz := clock_timestamp();
  v_count int := 0;
  v_months int;
begin
  select count(distinct m)
    into v_months
  from statements s,
       generate_series(date_trunc('month', s.period_start),
                       date_trunc('month', s.period_end),
                       interval '1 month') as m
  where s.account_id = p_account;

  if coalesce(v_months, 0) >= 3 then
    with months as (
      select distinct date_trunc('month', m)::date as month
      from statements s,
           generate_series(date_trunc('month', s.period_start),
                           date_trunc('month', s.period_end),
                           interval '1 month') as m
      where s.account_id = p_account
    ),
    latest as (
      select max(month) as lm from months
    ),
    base_months as (
      select month from months, latest
      where month < lm
      order by month desc
      limit 6
    ),
    all_months as (
      select month from base_months
      union
      select lm from latest
    ),
    cats as (
      select category from category_groups
      where group_name = 'variable_spending' and category <> 'travel'
    ),
    tx as (
      select t.category, date_trunc('month', t.date)::date as month, abs(t.amount) as amt
      from transactions t
      join statements s on s.id = t.statement_id
      where s.account_id = p_account
        and t.amount < 0
        and not t.is_reversal
    ),
    spend as (
      select c.category, am.month, coalesce(sum(tx.amt), 0) as total
      from cats c
      cross join all_months am
      left join tx on tx.category = c.category and tx.month = am.month
      group by c.category, am.month
    ),
    cmp as (
      select sp.category, l.lm,
             max(sp.total) filter (where sp.month = l.lm) as latest_total,
             avg(sp.total) filter (where sp.month <> l.lm) as base_avg,
             count(*) filter (where sp.month <> l.lm) as n_base
      from spend sp, latest l
      group by sp.category, l.lm
    ),
    found as (
      select category, lm, n_base,
             latest_total,
             round(base_avg, 2) as base_avg,
             round(latest_total - base_avg, 2) as diff,
             round((latest_total - base_avg) / base_avg * 100, 1) as pct,
             case when n_base >= 3 then 0.9 else 0.7 end as conf
      from cmp
      where n_base >= 2
        and base_avg > 0
        and latest_total > base_avg * 1.25
        and latest_total - base_avg >= 20
    )
    insert into signals (signal_key, account_id, signal_type, normalised_payee, category,
                         amount, previous_amount, monthly_impact, confidence, is_provisional,
                         rank_score, details, status, detected_at, updated_at)
    select p_account || '|spending_increase|' || category || '|' || to_char(lm, 'YYYY-MM'),
           p_account, 'spending_increase', null, category,
           latest_total, base_avg, diff, conf, false, round(diff * conf, 2),
           jsonb_build_object('month', to_char(lm, 'YYYY-MM'), 'increase_percent', pct,
                              'baseline_months', n_base),
           'new', v_run, v_run
    from found
    on conflict (signal_key) do update set
      amount          = excluded.amount,
      previous_amount = excluded.previous_amount,
      monthly_impact  = excluded.monthly_impact,
      confidence      = excluded.confidence,
      rank_score      = excluded.rank_score,
      details         = excluded.details,
      status          = case when signals.status = 'withdrawn' then 'new' else signals.status end,
      updated_at      = excluded.updated_at;

    get diagnostics v_count = row_count;
  end if;

  update signals
     set status = 'withdrawn', updated_at = v_run
   where account_id = p_account
     and signal_type = 'spending_increase'
     and status in ('new', 'shown')
     and updated_at < v_run;

  return v_count;
end;
$function$;
