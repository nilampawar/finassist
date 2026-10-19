-- Triggers (run after functions/*.sql)
CREATE TRIGGER trg_ensure_account BEFORE INSERT ON public.statements FOR EACH ROW EXECUTE FUNCTION ensure_account();
CREATE TRIGGER trg_apply_payee_alias BEFORE INSERT ON public.transactions FOR EACH ROW EXECUTE FUNCTION apply_payee_alias();
