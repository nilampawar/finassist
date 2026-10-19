-- FinAssist reference + demo data (run after 01_schema.sql)

-- 26 categories and their groups (used by the signal rules)
insert into category_groups (category, group_name) values
  ('apps', 'subscription'),
  ('broadcasting_fee', 'fixed_cost'),
  ('child_benefit', 'income'),
  ('donations', 'fixed_cost'),
  ('drugstore', 'variable_spending'),
  ('education', 'fixed_cost'),
  ('energy', 'fixed_cost'),
  ('fitness', 'subscription'),
  ('food_delivery', 'variable_spending'),
  ('groceries', 'variable_spending'),
  ('insurance', 'fixed_cost'),
  ('interest', 'other'),
  ('memberships', 'subscription'),
  ('music', 'subscription'),
  ('news_media', 'subscription'),
  ('other', 'other'),
  ('pension', 'income'),
  ('rent', 'fixed_cost'),
  ('salary', 'income'),
  ('shopping', 'variable_spending'),
  ('streaming', 'subscription'),
  ('student_aid', 'income'),
  ('telecom', 'fixed_cost'),
  ('transfer', 'other'),
  ('transport', 'subscription'),
  ('travel', 'variable_spending')
on conflict (category) do nothing;

-- Upload error messages shown to the user (English + German)
insert into failure_reasons (code, message_en, message_de, can_retry) values
  ('balance_mismatch', 'The amounts didn''t add up to the balance when we read this statement. Please try again or upload a CSV.', 'Beim Lesen haben die Beträge nicht zum Kontostand gepasst. Bitte versuche es erneut oder lade eine CSV-Datei hoch.', true),
  ('incomplete_response', 'We couldn''t read the whole statement. Please try again.', 'Wir konnten den Kontoauszug nicht vollständig lesen. Bitte versuche es erneut.', true),
  ('missing_account', 'We couldn''t find the account number (IBAN) on this statement.', 'Wir konnten auf diesem Kontoauszug keine IBAN finden.', false),
  ('missing_fields', 'Some key details (period or balances) are missing. A CSV export from your bank usually works.', 'Einige wichtige Angaben (Zeitraum oder Kontostand) fehlen. Ein CSV-Export deiner Bank funktioniert meist.', false),
  ('not_a_statement', 'This doesn''t look like a bank statement. Please upload a Kontoauszug (bank statement).', 'Das sieht nicht nach einem Kontoauszug aus. Bitte lade einen Kontoauszug hoch.', false),
  ('processing_error', 'Something went wrong while processing your file. Please try again.', 'Beim Verarbeiten ist etwas schiefgelaufen. Bitte versuche es erneut.', true),
  ('unknown_error', 'Something went wrong. Please try again.', 'Etwas ist schiefgelaufen. Bitte versuche es erneut.', true),
  ('unsupported_file_type', 'Please upload your bank statement as a PDF.', 'Bitte lade deinen Kontoauszug als PDF hoch.', false)
on conflict (code) do nothing;

-- Demo users (no passwords, no real login). email_alias = Gmail plus-address used to route emails.
insert into app_users (id, display_name, persona, data_sources, email_alias) values
  ('a0000000-0000-4000-8000-000000000001', 'Anna',  'Working professional', 'bank+gmail', 'finance'),
  ('a0000000-0000-4000-8000-000000000002', 'Ben',   'Student',              'bank+gmail', 'ben'),
  ('a0000000-0000-4000-8000-000000000003', 'Clara', 'Homemaker',            'bank+gmail', 'clara'),
  ('a0000000-0000-4000-8000-000000000004', 'Dana',  'Retiree',              'bank',       null)
on conflict (id) do nothing;

-- One account per demo user (IBAN stored masked only). Eval accounts are created automatically on upload.
insert into accounts (account_id, user_id, label) values
  ('DE00****0000', 'a0000000-0000-4000-8000-000000000001', 'Anna – working professional'),
  ('DE33****0033', 'a0000000-0000-4000-8000-000000000002', 'Ben – student'),
  ('DE44****0044', 'a0000000-0000-4000-8000-000000000003', 'Clara – homemaker'),
  ('DE55****0055', 'a0000000-0000-4000-8000-000000000004', 'Dana – retiree')
on conflict (account_id) do nothing;
