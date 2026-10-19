CREATE OR REPLACE FUNCTION public.detect_duplicate_subscriptions(p_account text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$declare
  v_run timestamptz := clock_timestamp();
  v_count int;
begin
  with subs as (
    select s.normalised_payee, s.category, s.amount, s.confidence, s.is_provisional
    from signals s
    join category_groups g on g.category = s.category
    where s.account_id = p_account
      and s.signal_type = 'recurring_payment'
      and s.status <> 'withdrawn'
      and g.group_name = 'subscription'
  ),
  dup as (
    select category,
           count(*) as n,
           sum(amount) as total,
           min(amount) as cheapest,
           min(confidence) as conf,
           bool_or(is_provisional) as prov,
           jsonb_agg(jsonb_build_object('payee', normalised_payee, 'amount', amount)
                     order by amount desc) as items
    from subs
    group by category
    having count(*) >= 2
  )
  insert into signals (signal_key, account_id, signal_type, normalised_payee, category,
                       amount, monthly_impact, confidence, is_provisional, rank_score,
                       details, status, detected_at, updated_at)
  select p_account || '|duplicate_subscription|' || category, p_account,
         'duplicate_subscription', null, category,
         total, cheapest, conf, prov, round(cheapest * conf, 2),
         jsonb_build_object('subscriptions', items, 'count', n),
         'new', v_run, v_run
  from dup
  on conflict (signal_key) do update set
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
     and signal_type = 'duplicate_subscription'
     and  status in ('new', 'shown')
     and updated_at < v_run;

  return v_count;
end;$function$;
