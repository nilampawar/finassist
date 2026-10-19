-- =====================================================================
-- Action flow – Step 3: save the agent's prepared action for one card.
-- Run once in the Supabase SQL Editor (new query, whole file, Run).
-- =====================================================================
create or replace function save_action(
  p_signal  uuid,
  p_account text,
  p_result  jsonb,
  p_money   jsonb,
  p_meta    jsonb
) returns jsonb
language plpgsql
as $$
declare
  v_id          uuid;
  v_options     jsonb := coalesce(p_result->'options', '[]'::jsonb);
  v_recommended text  := p_result->>'recommended';
begin
  -- unreadable or empty answer: do NOT save, so the card is retried in the next run
  if coalesce((p_result->>'unreadable')::boolean, false)
     or p_result->>'headline' is null
     or jsonb_array_length(coalesce(p_result->'options', '[]'::jsonb)) = 0 then
    return jsonb_build_object('action_id', null, 'saved', false, 'reason', 'unreadable_retry_later');
  end if;

  -- the recommended option must be one of the offered options, otherwise none
  if v_recommended is not null and not exists (
       select 1 from jsonb_array_elements(v_options) o where o->>'key' = v_recommended) then
    v_recommended := null;
  end if;

  insert into actions (signal_id, account_id, headline, options, recommended,
                       drafts, links, money, extras, model)
  values (p_signal, p_account,
          p_result->>'headline',
          v_options,
          v_recommended,
          coalesce(p_result->'drafts', '[]'::jsonb),
          coalesce(p_result->'links',  '[]'::jsonb),   -- already verified in n8n
          p_money,
          jsonb_build_object('meta', p_meta,
                             'unreadable', coalesce((p_result->>'unreadable')::boolean, false)),
          p_meta->>'model')
  on conflict (signal_id) do nothing                   -- one action per card, never twice
  returning id into v_id;

  return jsonb_build_object('action_id', v_id, 'already_existed', v_id is null);
end;
$$;
