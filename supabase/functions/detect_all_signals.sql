CREATE OR REPLACE FUNCTION public.detect_all_signals(p_account text)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  result jsonb := '{}'::jsonb;
begin
  result := result || jsonb_build_object('regular_income',         detect_regular_income(p_account));
  result := result || jsonb_build_object('recurring_payment',      detect_recurring_payments(p_account));
  result := result || jsonb_build_object('duplicate_subscription', detect_duplicate_subscriptions(p_account));
  result := result || jsonb_build_object('price_increase',         detect_price_increases(p_account));
  result := result || jsonb_build_object('unknown_debit',          detect_unknown_debits(p_account));
  result := result || jsonb_build_object('irregular_large_debit',  detect_irregular_large_debits(p_account));
  result := result || jsonb_build_object('spending_increase',      detect_spending_increases(p_account));
  return result;
end;
$function$;
