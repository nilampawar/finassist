CREATE OR REPLACE FUNCTION public.apply_payee_alias()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
declare
  v_account text;
  v_name text;
begin
  if new.payee is null then
    return new;
  end if;

  select account_id into v_account from statements where id = new.statement_id;

  select normalised_payee into v_name
  from payee_aliases
  where account_id = v_account and raw_payee = new.payee;

  if v_name is not null then
    new.normalised_payee := v_name;
  else
    insert into payee_aliases (account_id, raw_payee, normalised_payee)
    values (v_account, new.payee, coalesce(new.normalised_payee, new.payee))
    on conflict do nothing;
  end if;

  return new;
end;
$function$;
