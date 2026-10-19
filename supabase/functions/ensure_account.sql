CREATE OR REPLACE FUNCTION public.ensure_account()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  insert into accounts (account_id) values (new.account_id)
  on conflict do nothing;
  return new;
end;
$function$;
