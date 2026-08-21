-- Adds per-call-site attribution to api_call_cost_log — consolidated
-- small-fixes build, 2026-08-21.
--
-- Why: `function_name` is the EDGE FUNCTION ('ask-chef-harris'), identical on
-- every row, so the table has never been able to answer "which surface cost
-- what". The 2026-08-21 numbers session had to infer per-surface attribution
-- by clustering on prompt_tokens and timing and cross-checking against a
-- commit message — workable for one controlled burst, useless for real usage.
-- This column makes it a stored fact.
--
-- Nullable and unconstrained on purpose:
-- - Nullable: every existing row predates this, and a call that arrives with
--   no surface records null rather than being guessed into a bucket. Same
--   principle as cached_tokens (migration 20260818120000) — a null must never
--   be confused with a measured value.
-- - No CHECK constraint and no enum: the client owns the vocabulary
--   (kChefCallSurfaces in lib/services/chef_service.dart). A constraint here
--   would mean a new surface could not ship without a migration, and the
--   failure mode would be a lost cost row on a working feature. The set is
--   small and changes with the UI — it changed on 2026-08-20 when
--   _ChefSuggestionSheet was deleted.
--
-- Index: the useful query is "cost per surface over a window", which is why
-- this mirrors the existing (function_name, created_at) index shape.
-- NOTE: This migration is safe to re-run (IF NOT EXISTS guards).

alter table public.api_call_cost_log
  add column if not exists surface text;

create index if not exists idx_api_call_cost_log_surface_created
  on public.api_call_cost_log (surface, created_at);
