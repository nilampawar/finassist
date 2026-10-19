CREATE OR REPLACE FUNCTION public.get_signals_for_actions(p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  select coalesce(jsonb_agg(x order by x.detected_at), '[]'::jsonb)
  from (
    select
      s.id                         as signal_id,
      s.account_id,
      u.display_name               as first_name,
      s.signal_type,
      s.normalised_payee           as provider,
      s.category,
      s.amount,
      s.previous_amount,
      s.details,
      s.detected_at,

      -- MONEY: calculated here, never by the AI
      jsonb_build_object(
        'monthly_change',
          case when s.signal_type in ('price_change','price_increase') and s.previous_amount is not null
               then round(s.amount - s.previous_amount, 2) end,
        'extra_per_year',
          case when s.signal_type in ('price_change','price_increase') and s.previous_amount is not null
               then round((s.amount - s.previous_amount) * 12, 2) end,
        'cost_per_year_if_kept',          -- e.g. a free trial turning paid
          case when s.signal_type = 'price_change' and s.previous_amount is null
               then round(s.amount * 12, 2) end,
        'duplicate_monthly_total',
          case when s.signal_type = 'duplicate_subscription' then s.amount end,
        'saving_per_year_if_cheapest_cancelled',   -- keep one, cancel the cheaper one
          case when s.signal_type = 'duplicate_subscription' then (
            select round(min((sub->>'amount')::numeric) * 12, 2)
            from jsonb_array_elements(coalesce(s.details->'subscriptions', '[]'::jsonb)) sub) end,
        'amount_at_stake',
          case when s.signal_type in ('pending_payment','upcoming_bill','needs_check',
                                      'unknown_debit','irregular_large_debit') then s.amount end,
        'trip_days',
          case when s.signal_type = 'travel_booking'
               then (s.details->>'travel_end')::date - (s.details->>'travel_start')::date end,
        'trip_pause_saving_up_to',        -- pausable subscriptions x trip length
          case when s.signal_type = 'travel_booking' then (
            select round(sum(r.amount) *
                   (((s.details->>'travel_end')::date - (s.details->>'travel_start')::date) / 30.0), 2)
            from signals r
            where r.account_id = s.account_id and r.signal_type = 'recurring_payment'
              and r.status <> 'withdrawn'
              and r.category in ('fitness','transport','streaming','music','memberships')) end,
        'refund_amount',
          case when s.signal_type = 'refund_offer' then s.amount end,
        'voucher_amount',
          case when s.signal_type = 'refund_offer' then (s.details->>'voucher_amount')::numeric end,
        'voucher_extra_value',            -- how much more the voucher is worth than the cash refund
          case when s.signal_type = 'refund_offer' and s.details->>'voucher_amount' is not null
               then round((s.details->>'voucher_amount')::numeric - s.amount, 2) end,
        'cost_per_year_at_new_price',      -- what keeping it costs per year (for "cancel" / "switch" options)
          case when s.signal_type in ('price_change','price_increase') then round(s.amount * 12, 2) end,
        'per_subscription_per_year',       -- duplicate subscriptions: what cancelling EACH one saves per year
          case when s.signal_type = 'duplicate_subscription' then (
            select jsonb_agg(jsonb_build_object('payee', sub->>'payee',
                                                'monthly', (sub->>'amount')::numeric,
                                                'per_year', round((sub->>'amount')::numeric * 12, 2)))
            from jsonb_array_elements(coalesce(s.details->'subscriptions', '[]'::jsonb)) sub) end,
        'pause_saving_per_subscription',   -- travel: what pausing EACH subscription saves during the trip
          case when s.signal_type = 'travel_booking' then (
            select jsonb_agg(jsonb_build_object('provider', r.normalised_payee, 'monthly', r.amount,
                   'saving_during_trip', round(r.amount *
                     (((s.details->>'travel_end')::date - (s.details->>'travel_start')::date) / 30.0), 2)))
            from signals r
            where r.account_id = s.account_id and r.signal_type = 'recurring_payment'
              and r.status <> 'withdrawn'
              and r.category in ('fitness','transport','streaming','music','memberships')) end,
        'deadline', coalesce(s.details->>'due_date', s.details->>'travel_start')
      ) as money,

      -- TRAVEL: which regular payments could be paused during the trip
      case when s.signal_type = 'travel_booking' then (
        select coalesce(jsonb_agg(jsonb_build_object('provider', r.normalised_payee,
                                                     'amount', r.amount, 'category', r.category)), '[]'::jsonb)
        from signals r
        where r.account_id = s.account_id and r.signal_type = 'recurring_payment'
          and r.status <> 'withdrawn'
          and r.category in ('fitness','transport','streaming','music','memberships')
      ) end as pausable_subscriptions

    from signals s
    join accounts a       on a.account_id = s.account_id
    join app_users u      on u.id = a.user_id     -- only real (demo) users, not eval test accounts
    where s.status <> 'withdrawn'
      and ( s.details->>'needs_attention' = 'true'
            or s.signal_type in ('price_increase','duplicate_subscription','unknown_debit',
                                 'irregular_large_debit','spending_increase','needs_check','refund_offer') )
      and not exists (select 1 from actions ac where ac.signal_id = s.id)
    order by s.detected_at
    limit p_limit
  ) x;
$function$;
