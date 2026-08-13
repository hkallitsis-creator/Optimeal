-- Create api_call_cost_log: durable, per-call token/cost history for AI
-- edge function calls. Separate from api_usage_daily (which only tracks
-- call COUNTS for cap enforcement) — this table exists purely for Harris's
-- own cost observability, written server-side by edge functions using the
-- service role key. See CLAUDE.md roadmap item 11 follow-up (2026-08-13).
-- NOTE: This migration is safe to re-run (IF NOT EXISTS guards).

create table if not exists public.api_call_cost_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users (id) on delete cascade,
  function_name text not null,
  model text not null,
  prompt_tokens int not null,
  completion_tokens int not null,
  -- Rate actually used for THIS row, stored alongside the computed cost so
  -- old rows stay individually verifiable even after pricing constants are
  -- updated later — see OPENAI_PRICING_PER_MILLION_TOKENS in
  -- supabase/functions/ask-chef-harris/index.ts for the current rates.
  input_rate_per_million numeric not null,
  output_rate_per_million numeric not null,
  cost_usd numeric not null,
  created_at timestamptz not null default now()
);

create index if not exists idx_api_call_cost_log_user_created on public.api_call_cost_log (user_id, created_at);
create index if not exists idx_api_call_cost_log_function_created on public.api_call_cost_log (function_name, created_at);

alter table public.api_call_cost_log enable row level security;

-- Deliberately NO policies and NO grants for `authenticated`/`anon` —
-- unlike api_usage_daily (an owner-scoped, client-facing feature: users
-- read/write their own cap-check rows), this table is pure cost
-- observability for Harris, not a user-facing feature. No client ever
-- needs to read it. Only edge functions using the service role key (which
-- bypasses RLS entirely) touch this table — same pattern already used for
-- ai_precision_cache (see CLAUDE.md Supabase RLS section). Do NOT copy the
-- api_usage_daily grant pattern onto this table.
