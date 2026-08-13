-- Fix: service_role had no INSERT/SELECT grant on api_call_cost_log — the
-- exact same class of bug already found and fixed for api_usage_daily on
-- 2026-08-11 ("RLS policies and table-level grants are two separate
-- Postgres mechanisms": bypassrls only skips RLS policies, it does NOT
-- grant table-level SQL privileges on its own). Confirmed via
-- information_schema.role_table_grants: service_role only had
-- TRUNCATE/REFERENCES/TRIGGER, no INSERT/SELECT. This silently broke the
-- ask-chef-harris edge function's cost-log write — no error surfaced to
-- the client, since logCallCost()'s own try/catch swallowed it and
-- console.error only goes to Supabase Dashboard logs, not visible via the
-- CLI. Confirmed live: 5 real Fridge Clearer generations landed 0 rows in
-- api_call_cost_log before this fix.
-- NOTE: This migration is safe to re-run (grant is idempotent).

grant select, insert on public.api_call_cost_log to service_role;
