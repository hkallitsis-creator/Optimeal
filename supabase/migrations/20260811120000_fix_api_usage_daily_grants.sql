-- Fix: api_usage_daily was created (2026-08-10) without table-level GRANTs
-- to the authenticated role. RLS policies control row visibility but do NOT
-- substitute for table-level privileges -- Postgres checks both, and without
-- this GRANT every query hit 42501 "permission denied for table
-- api_usage_daily" regardless of the RLS policies already in place.
-- Confirmed via a live app run (2026-08-11): UsageCapService calls against
-- this table failed with exactly that error, while user_profiles and
-- user_meal_plans (which already carry full CRUD grants to authenticated,
-- likely inherited from schema-level default privileges at the time they
-- were created) worked fine. Root cause of the gap wasn't pinned down, but
-- this migration doesn't rely on default privileges applying automatically
-- again -- future table migrations should include explicit GRANTs too.
-- NOTE: Safe to re-run.

grant select, insert, update on public.api_usage_daily to authenticated;
grant execute on function public.increment_api_usage(text) to authenticated;
