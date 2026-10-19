CREATE OR REPLACE FUNCTION public.save_statement(p_file_id text, p_file_name text, p_statement jsonb, p_transactions jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
declare
  v_upload uuid;
  v_statement uuid;
  v_existed boolean := false;
  v_saved int;
begin
  -- 1. Upload record
  insert into uploads (file_id, file_name, status, updated_at)
  values (p_file_id, p_file_name, 'processing', now())
  on conflict (file_id) do update set
    file_name = coalesce(excluded.file_name, uploads.file_name),
    status = 'processing', failure_reason = null, updated_at = now()
  returning id into v_upload;

  -- 2. Statement (skipped if it already exists)
  insert into statements (idempotency_key, upload_id, account_id, period_start, period_end,
                          opening_balance, closing_balance)
  values (p_statement->>'statement_key', v_upload, p_statement->>'account_id',
          (p_statement->>'period_start')::date, (p_statement->>'period_end')::date,
          (p_statement->>'opening_balance')::numeric, (p_statement->>'closing_balance')::numeric)
  on conflict (idempotency_key) do nothing
  returning id into v_statement;

  if v_statement is null then
    select id into v_statement from statements
    where idempotency_key = p_statement->>'statement_key';
    v_existed := true;
  end if;

  -- 3. Transactions (duplicates skipped)
  insert into transactions (idempotency_key, statement_id, date, type, payee, normalised_payee,
                            description, amount, category, is_reversal)
  select t->>'idempotency_key', v_statement, (t->>'date')::date, t->>'type', t->>'payee',
         t->>'normalised_payee', t->>'description', (t->>'amount')::numeric, t->>'category',
         coalesce((t->>'is_reversal')::boolean, false)
  from jsonb_array_elements(p_transactions) as t
  on conflict (idempotency_key) do nothing;

  get diagnostics v_saved = row_count;

  -- 4. Mark the upload as done
  perform record_upload_status(p_file_id, p_file_name, 'done', null);

  return jsonb_build_object(
    'upload_id', v_upload,
    'statement_id', v_statement,
    'account_id', p_statement->>'account_id',
    'statement_already_existed', v_existed,
    'transactions_saved', v_saved
  );
end;
$function$;
