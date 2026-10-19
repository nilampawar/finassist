CREATE OR REPLACE FUNCTION public.record_upload_status(p_file_id text, p_file_name text, p_status text, p_reason text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
AS $function$
declare
  v_reason text;
  v_id uuid;
begin
  if p_status = 'failed' then
    select code into v_reason from failure_reasons where code = p_reason;
    v_reason := coalesce(v_reason, 'unknown_error');
  else
    v_reason := null;
  end if;

  insert into uploads (file_id, file_name, status, failure_reason, updated_at)
  values (p_file_id, p_file_name, p_status, v_reason, now())
  on conflict (file_id) do update set
    file_name      = coalesce(excluded.file_name, uploads.file_name),
    status         = excluded.status,
    failure_reason = excluded.failure_reason,
    updated_at     = now()
  returning id into v_id;

  return v_id;
end;
$function$;
