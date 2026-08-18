-- Adds cached-token capture to api_call_cost_log — prompt-caching
-- investigation/perf session, 2026-08-18. Real dev measurements confirmed
-- OpenAI's automatic prompt caching already engages on this app's static
-- system prompt (ask-chef-harris), but nothing recorded HOW MUCH of a
-- given call's prompt_tokens were actually served from cache — this
-- column is what that measurement needs going forward, not just for a
-- one-off session.
--
-- Nullable: existing rows (and any future insert path that doesn't have
-- usage.prompt_tokens_details.cached_tokens, e.g. an older deployed
-- function version) simply record null, not 0 — 0 would falsely claim
-- "measured and confirmed zero cached tokens" for a row that was never
-- actually measured.
-- NOTE: This migration is safe to re-run (IF NOT EXISTS guard).

alter table public.api_call_cost_log
  add column if not exists cached_tokens int;
