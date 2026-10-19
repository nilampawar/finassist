-- =====================================================================
-- F6: "Mark as done" / "Not relevant" closes the card everywhere
-- The app only ADDS a feedback row (as before). This trigger, running
-- inside the database, then updates the signal's status:
--   done          -> acted
--   not_relevant  -> dismissed
-- The app gets no new permission. The 7 bank rules already keep these
-- statuses, so a closed card does not come back after a re-upload.
-- Run once in the Supabase SQL Editor (new query, whole file, Run).
-- =====================================================================

create or replace function close_signal_on_feedback()
returns trigger
language plpgsql
security definer                       -- runs with the table owner's rights, not the app's
set search_path = public
as $$
begin
  if new.signal_id is not null and new.value in ('done', 'not_relevant') then
    update signals
       set status     = case when new.value = 'done' then 'acted' else 'dismissed' end,
           updated_at = now()
     where id = new.signal_id
       and account_id = new.account_id          -- only the user's own card
       and status in ('new', 'shown');          -- never re-open or overwrite withdrawn cards
  end if;
  return new;
end;
$$;

drop trigger if exists trg_close_signal_on_feedback on feedback;
create trigger trg_close_signal_on_feedback
  after insert on feedback
  for each row execute function close_signal_on_feedback();

-- One-time catch-up: cards already marked done / not relevant before this trigger existed
update signals s
   set status     = case when f.value = 'done' then 'acted' else 'dismissed' end,
       updated_at = now()
  from (select distinct on (signal_id) signal_id, account_id, value
          from feedback
         where signal_id is not null and value in ('done', 'not_relevant')
         order by signal_id, created_at desc) f
 where s.id = f.signal_id
   and s.account_id = f.account_id
   and s.status in ('new', 'shown');

-- Check: which cards are closed now?
-- select account_id, signal_type, normalised_payee, status from signals
-- where status in ('acted', 'dismissed') order by account_id;
