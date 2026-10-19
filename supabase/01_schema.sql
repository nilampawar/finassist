-- FinAssist database schema (Supabase / Postgres)
-- Run order: 01_schema.sql -> 02_seed.sql -> functions/*.sql -> 03_triggers.sql
-- Generated from the live database.

-- 1) TABLES
create table if not exists accounts (
  account_id text not null,
  user_id uuid,
  label text,
  created_at timestamp with time zone default now()
);

create table if not exists actions (
  id uuid not null default gen_random_uuid(),
  signal_id uuid not null,
  account_id text not null,
  headline text,
  options jsonb,
  recommended text,
  drafts jsonb,
  links jsonb,
  money jsonb,
  extras jsonb,
  model text,
  created_at timestamp with time zone not null default now()
);

create table if not exists app_users (
  id uuid not null default gen_random_uuid(),
  display_name text not null,
  persona text,
  data_sources text,
  email_alias text,
  is_demo boolean not null default true,
  created_at timestamp with time zone not null default now()
);

create table if not exists category_groups (
  category text not null,
  group_name text not null
);

create table if not exists failure_reasons (
  code text not null,
  message_en text not null,
  message_de text not null,
  can_retry boolean not null default false
);

create table if not exists feedback (
  id uuid not null default gen_random_uuid(),
  account_id text not null,
  signal_id uuid,
  action_id uuid,
  element text not null,
  value text not null,
  created_at timestamp with time zone not null default now()
);

create table if not exists payee_aliases (
  account_id text not null,
  raw_payee text not null,
  normalised_payee text not null,
  created_at timestamp with time zone default now()
);

create table if not exists processed_emails (
  email_id text not null,
  account_id text not null,
  received_at date,
  email_type text not null,
  category text,
  provider text,
  amount numeric,
  previous_amount numeric,
  due_date date,
  travel_start date,
  travel_end date,
  is_for_user boolean,
  needs_attention boolean,
  reason text,
  signal_id uuid,
  created_at timestamp with time zone default now()
);

create table if not exists provider_links (
  id uuid not null default gen_random_uuid(),
  provider_key text not null,
  link_type text not null,
  label text not null,
  url text not null
);

create table if not exists signals (
  id uuid not null default gen_random_uuid(),
  signal_key text not null,
  account_id text not null,
  signal_type text not null,
  normalised_payee text,
  category text,
  amount numeric,
  previous_amount numeric,
  monthly_impact numeric,
  confidence numeric,
  is_provisional boolean not null default false,
  rank_score numeric,
  details jsonb,
  status text not null default 'new'::text,
  detected_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

create table if not exists statements (
  id uuid not null default gen_random_uuid(),
  idempotency_key text not null,
  upload_id uuid,
  account_id text not null,
  period_start date not null,
  period_end date not null,
  opening_balance numeric not null,
  closing_balance numeric not null,
  created_at timestamp with time zone default now()
);

create table if not exists transactions (
  id uuid not null default gen_random_uuid(),
  idempotency_key text not null,
  statement_id uuid not null,
  date date not null,
  type text,
  payee text,
  normalised_payee text,
  description text,
  amount numeric not null,
  category text,
  is_reversal boolean not null default false,
  created_at timestamp with time zone default now()
);

create table if not exists uploads (
  id uuid not null default gen_random_uuid(),
  file_id text not null,
  file_name text,
  status text not null default 'processing'::text,
  failure_reason text,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now()
);

-- 2) CONSTRAINTS (primary/unique keys, checks, then foreign keys)
alter table accounts add constraint accounts_pkey PRIMARY KEY (account_id);
alter table actions add constraint actions_pkey PRIMARY KEY (id);
alter table actions add constraint actions_signal_id_key UNIQUE (signal_id);
alter table app_users add constraint app_users_email_alias_key UNIQUE (email_alias);
alter table app_users add constraint app_users_pkey PRIMARY KEY (id);
alter table category_groups add constraint category_groups_pkey PRIMARY KEY (category);
alter table failure_reasons add constraint failure_reasons_pkey PRIMARY KEY (code);
alter table feedback add constraint feedback_pkey PRIMARY KEY (id);
alter table payee_aliases add constraint payee_aliases_pkey PRIMARY KEY (account_id, raw_payee);
alter table processed_emails add constraint processed_emails_pkey PRIMARY KEY (email_id);
alter table provider_links add constraint provider_links_pkey PRIMARY KEY (id);
alter table provider_links add constraint provider_links_provider_key_link_type_url_key UNIQUE (provider_key, link_type, url);
alter table signals add constraint signals_pkey PRIMARY KEY (id);
alter table signals add constraint signals_signal_key_key UNIQUE (signal_key);
alter table statements add constraint statements_idempotency_key_key UNIQUE (idempotency_key);
alter table statements add constraint statements_pkey PRIMARY KEY (id);
alter table transactions add constraint transactions_idempotency_key_key UNIQUE (idempotency_key);
alter table transactions add constraint transactions_pkey PRIMARY KEY (id);
alter table uploads add constraint uploads_file_id_key UNIQUE (file_id);
alter table uploads add constraint uploads_pkey PRIMARY KEY (id);
alter table category_groups add constraint category_groups_group_name_check CHECK ((group_name = ANY (ARRAY['fixed_cost'::text, 'subscription'::text, 'variable_spending'::text, 'income'::text, 'other'::text])));
alter table feedback add constraint feedback_element_check CHECK ((element = ANY (ARRAY['card'::text, 'option'::text, 'draft_email'::text, 'link'::text, 'weather'::text, 'tip'::text])));
alter table feedback add constraint feedback_value_check CHECK (((value = ANY (ARRAY['helpful'::text, 'not_helpful'::text, 'done'::text, 'not_relevant'::text])) OR (value ~~ 'chose:%'::text)));
alter table processed_emails add constraint processed_emails_email_type_check CHECK ((email_type = ANY (ARRAY['refund_offer'::text, 'upcoming_bill'::text, 'price_change'::text, 'pending_payment'::text, 'travel_booking'::text, 'ignore'::text, 'uncertain'::text])));
alter table provider_links add constraint provider_links_link_type_check CHECK ((link_type = ANY (ARRAY['website'::text, 'cancel'::text, 'contact'::text, 'compare'::text])));
alter table signals add constraint signals_confidence_check CHECK (((confidence >= (0)::numeric) AND (confidence <= (1)::numeric)));
alter table signals add constraint signals_signal_type_check CHECK ((signal_type = ANY (ARRAY['refund_offer'::text, 'needs_check'::text, 'regular_income'::text, 'recurring_payment'::text, 'duplicate_subscription'::text, 'price_increase'::text, 'unknown_debit'::text, 'irregular_large_debit'::text, 'spending_increase'::text, 'upcoming_bill'::text, 'price_change'::text, 'pending_payment'::text, 'travel_booking'::text])));
alter table signals add constraint signals_status_check CHECK ((status = ANY (ARRAY['new'::text, 'shown'::text, 'dismissed'::text, 'acted'::text, 'withdrawn'::text])));
alter table uploads add constraint uploads_status_check CHECK ((status = ANY (ARRAY['processing'::text, 'done'::text, 'failed'::text])));
alter table accounts add constraint accounts_user_id_fkey FOREIGN KEY (user_id) REFERENCES app_users(id);
alter table actions add constraint actions_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(account_id);
alter table actions add constraint actions_signal_id_fkey FOREIGN KEY (signal_id) REFERENCES signals(id) ON DELETE CASCADE;
alter table feedback add constraint feedback_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(account_id);
alter table feedback add constraint feedback_action_id_fkey FOREIGN KEY (action_id) REFERENCES actions(id) ON DELETE CASCADE;
alter table feedback add constraint feedback_signal_id_fkey FOREIGN KEY (signal_id) REFERENCES signals(id) ON DELETE CASCADE;
alter table payee_aliases add constraint fk_payee_aliases_account FOREIGN KEY (account_id) REFERENCES accounts(account_id);
alter table processed_emails add constraint processed_emails_account_id_fkey FOREIGN KEY (account_id) REFERENCES accounts(account_id);
alter table processed_emails add constraint processed_emails_category_fkey FOREIGN KEY (category) REFERENCES category_groups(category);
alter table processed_emails add constraint processed_emails_signal_id_fkey FOREIGN KEY (signal_id) REFERENCES signals(id) ON DELETE SET NULL;
alter table signals add constraint fk_signals_account FOREIGN KEY (account_id) REFERENCES accounts(account_id);
alter table signals add constraint fk_signals_category FOREIGN KEY (category) REFERENCES category_groups(category);
alter table statements add constraint fk_statements_account FOREIGN KEY (account_id) REFERENCES accounts(account_id);
alter table statements add constraint statements_upload_id_fkey FOREIGN KEY (upload_id) REFERENCES uploads(id) ON DELETE SET NULL;
alter table transactions add constraint fk_transactions_category FOREIGN KEY (category) REFERENCES category_groups(category);
alter table transactions add constraint transactions_statement_id_fkey FOREIGN KEY (statement_id) REFERENCES statements(id) ON DELETE CASCADE;
alter table uploads add constraint fk_uploads_failure_reason FOREIGN KEY (failure_reason) REFERENCES failure_reasons(code);

-- 3) ROW LEVEL SECURITY: on for every table. Without a policy, the app (anon key) sees nothing;
--    n8n uses the server key and is not affected. The app may only READ demo users' data and ADD feedback.
alter table accounts enable row level security;
alter table actions enable row level security;
alter table app_users enable row level security;
alter table category_groups enable row level security;
alter table failure_reasons enable row level security;
alter table feedback enable row level security;
alter table payee_aliases enable row level security;
alter table processed_emails enable row level security;
alter table provider_links enable row level security;
alter table signals enable row level security;
alter table statements enable row level security;
alter table transactions enable row level security;
alter table uploads enable row level security;

create policy "UI can read demo users accounts" on accounts for select to anon
  using ((user_id IN ( SELECT app_users.id
   FROM app_users
  WHERE app_users.is_demo)));

create policy "UI can read demo users actions" on actions for select to anon
  using ((account_id IN ( SELECT accounts.account_id
   FROM accounts
  WHERE (accounts.user_id IN ( SELECT app_users.id
           FROM app_users
          WHERE app_users.is_demo)))));

create policy "UI can read demo users" on app_users for select to anon
  using (is_demo);

create policy "UI can add feedback for demo users" on feedback for insert to anon
  with check ((account_id IN ( SELECT accounts.account_id
   FROM accounts
  WHERE (accounts.user_id IN ( SELECT app_users.id
           FROM app_users
          WHERE app_users.is_demo)))));

create policy "UI can read provider links" on provider_links for select to anon
  using (true);

create policy "UI can read demo users signals" on signals for select to anon
  using ((account_id IN ( SELECT accounts.account_id
   FROM accounts
  WHERE (accounts.user_id IN ( SELECT app_users.id
           FROM app_users
          WHERE app_users.is_demo)))));

