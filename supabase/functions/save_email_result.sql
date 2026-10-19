CREATE OR REPLACE FUNCTION public.save_email_result(p_account text, p_email_id text, p_result jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_type text := coalesce(p_result->>'type', 'uncertain');
  v_reason text := null;  -- only short rule codes are stored, never the agent's free text (privacy)
  v_cat text := p_result->>'category';
  v_amount numeric := nullif(p_result->>'amount', '')::numeric;
  v_prev numeric := nullif(p_result->>'previous_amount', '')::numeric;
  v_due date := nullif(p_result->>'due_date', '')::date;
  v_start date := nullif(p_result->>'travel_start', '')::date;
  v_end date := nullif(p_result->>'travel_end', '')::date;
  v_key_date date;
  v_signal uuid;
  v_impact numeric;
  v_attention boolean := coalesce((p_result->>'needs_attention')::boolean, true);
begin
  -- Decide once: an email already processed keeps its stored answer
  if exists (select 1 from processed_emails where email_id = p_email_id) then
    return (select jsonb_build_object('already_processed', true,
                                      'type', email_type, 'signal_id', signal_id)
            from processed_emails where email_id = p_email_id);
  end if;

  -- Rule: category must exist, otherwise 'other'
  if v_cat is null or not exists (select 1 from category_groups where category = v_cat) then
    v_cat := 'other';
  end if;

  -- Rule: only known types
  if v_type not in ('upcoming_bill', 'price_change', 'pending_payment',
                    'travel_booking', 'refund_offer', 'ignore', 'uncertain') then
    v_type := 'uncertain';
    v_reason := 'unknown_type';
  end if;

  -- Rule: a travel booking for someone else is ignored
  if v_type = 'travel_booking' and coalesce((p_result->>'is_for_user')::boolean, false) = false then
    v_type := 'ignore';
    v_reason := 'not_for_user';
  end if;

  -- CHANGED: past dates
  -- An unpaid pending payment stays (overdue); other types with a past date are ignored
  v_key_date := coalesce(v_start, v_due);
  if v_type = 'pending_payment' and v_due is not null and v_due < current_date then
    v_reason := 'overdue';
  elsif v_type not in ('ignore', 'uncertain', 'pending_payment')
        and v_key_date is not null and v_key_date < current_date then
    v_type := 'ignore';
    v_reason := 'date_passed';
  end if;

  -- Rule: bills, price changes and pending payments need an amount and a date
  if v_type in ('upcoming_bill', 'price_change', 'pending_payment')
     and (v_amount is null or v_due is null) then
    v_type := 'uncertain';
    v_reason := 'missing_amount_or_date';
  end if;

  -- NEW (v6) Rule: a refund offer needs at least the refund amount
  if v_type = 'refund_offer' and v_amount is null then
    v_type := 'uncertain';
    v_reason := 'missing_amount_or_date';
  end if;

  -- NEW (v5) Rule: a higher price on a recurring payment always needs attention (money fact, decided by code)
  if v_type = 'price_change' and v_amount is not null and v_prev is not null and v_amount > v_prev then
    v_attention := true;
  end if;

  -- NEW (v5) Rule: the same bill arriving as a second email (resent, forwarded) creates no second card.
  -- Compares CONTENT (type, provider, amount, date), because every copy has a new Gmail message id.
  if v_type in ('upcoming_bill', 'price_change', 'pending_payment', 'travel_booking', 'refund_offer')
     and exists (
       select 1 from signals s
       where s.account_id = p_account
         and s.details->>'source' = 'email'
         and s.status <> 'withdrawn'
         and s.signal_type = v_type
         and lower(coalesce(s.normalised_payee, '')) = lower(coalesce(p_result->>'provider', ''))
         and s.amount is not distinct from v_amount
         and coalesce(s.details->>'due_date', s.details->>'travel_start', '')
             = coalesce(v_due::text, v_start::text, '')
     ) then
    v_type := 'ignore';
    v_reason := 'duplicate';
  end if;

  -- Create a signal for the useful types, and for doubts the user should check
  if v_type in ('upcoming_bill', 'price_change', 'pending_payment', 'travel_booking', 'refund_offer')
     or (v_type = 'uncertain' and v_attention) then
    v_impact := case when v_type = 'price_change' then coalesce(v_amount, 0) - coalesce(v_prev, 0)
                     when v_type = 'uncertain' then 0
                     else coalesce(v_amount, 0) end;

    insert into signals (signal_key, account_id, signal_type, normalised_payee, category,
                         amount, previous_amount, monthly_impact, confidence, is_provisional,
                         rank_score, details, status, detected_at, updated_at)
    values (p_account || '|' || v_type || '|' || p_email_id, p_account,
            case when v_type = 'uncertain' then 'needs_check' else v_type end,
            p_result->>'provider', v_cat, v_amount, v_prev, v_impact,
            case when v_type = 'uncertain' then 0.5 else 0.9 end, false,
            round(coalesce(v_impact, 0) * 0.9, 2),
            jsonb_build_object('source', 'email', 'due_date', v_due,
                               'travel_start', v_start, 'travel_end', v_end,
                               'overdue', v_reason = 'overdue',
                               'needs_attention', v_attention,
                               'suggestion', p_result->>'suggestion',
                               'voucher_amount', nullif(p_result->>'voucher_amount', '')::numeric,
                               'reason', v_reason),
            'new', now(), now())
    on conflict (signal_key) do nothing
    returning id into v_signal;
  end if;

  insert into processed_emails (email_id, account_id, received_at, email_type, category, provider,
                                amount, previous_amount, due_date, travel_start, travel_end,
                                is_for_user, needs_attention, reason, signal_id)
  values (p_email_id, p_account, nullif(p_result->>'received_at', '')::date, v_type, v_cat,
          p_result->>'provider', v_amount, v_prev, v_due, v_start, v_end,
          (p_result->>'is_for_user')::boolean, case when v_type = 'ignore' then false else v_attention end,
          v_reason, v_signal);

  return jsonb_build_object('already_processed', false, 'type', v_type, 'category', v_cat,
                            'reason', v_reason, 'signal_id', v_signal);
end;
$function$;
