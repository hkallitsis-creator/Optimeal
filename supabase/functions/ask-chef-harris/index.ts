import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};

// Single named source for OpenAI pricing (USD per 1M tokens). Update the
// numbers AND this date whenever rates are re-verified — see CLAUDE.md
// roadmap item 11 for the durable-cost-history design this feeds.
//
// `cachedInput` added 2026-08-21. Prompt tokens served from OpenAI's
// automatic prefix cache are billed at half rate, and cost_usd was charging
// ALL prompt tokens at the full input rate — a ~14% overstatement measured
// across the 13 cache-aware rows on dev, and one that grows as hit rates do.
// Rates checked 2026-08-21 against OpenAI's published pricing
// (https://developers.openai.com/api/docs/pricing).
const OPENAI_PRICING_PER_MILLION_TOKENS: Record<string, { input: number; cachedInput: number; output: number }> = {
  'gpt-4o': { input: 2.50, cachedInput: 1.25, output: 10.00 },
  'gpt-4o-mini': { input: 0.15, cachedInput: 0.075, output: 0.60 }
};

// Decodes the `sub` (user id) claim out of the caller's JWT without a
// network round-trip. Safe to trust without re-verifying the signature
// here: this project's supabase/config.toml sets `verify_jwt = true` for
// this function, so the Supabase Edge Runtime already cryptographically
// validated the token before invoking this handler at all.
function decodeUserIdFromAuthHeader(authHeader: string | null): string | null {
  if (!authHeader) return null;
  const token = authHeader.replace(/^Bearer\s+/i, '');
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  try {
    const payloadJson = atob(parts[1].replace(/-/g, '+').replace(/_/g, '/'));
    const payload = JSON.parse(payloadJson);
    return typeof payload?.sub === 'string' ? payload.sub : null;
  } catch {
    return null;
  }
}

// Inserts into api_call_cost_log using the service role key (bypasses
// RLS — the table has zero authenticated/anon policies by design, see the
// migration). Callers await this, but it's wrapped in try/catch so a
// logging failure can never turn into a failed recipe response — same
// fail-open principle UsageCapService already uses client-side.
async function logCallCost(row: {
  userId: string | null;
  functionName: string;
  model: string;
  promptTokens: number;
  completionTokens: number;
  inputRatePerMillion: number;
  outputRatePerMillion: number;
  costUsd: number;
  // Prompt-caching investigation (2026-08-18) — see
  // usage.prompt_tokens_details.cached_tokens below. Null (not 0) when the
  // upstream response has no usage detail to read this from, so a null
  // row never falsely claims "measured and confirmed zero cached tokens".
  cachedTokens: number | null;
  // Which client call site produced this call (2026-08-21). Null when the
  // caller didn't send one — never guessed, since a wrong attribution is
  // worse than a missing one. See kChefCallSurfaces in
  // lib/services/chef_service.dart for the values the app actually sends;
  // this function deliberately does not validate against that list, so a new
  // surface can ship client-side without a redeploy.
  surface: string | null;
}) {
  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !serviceRoleKey) {
      console.error('logCallCost: missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY');
      return;
    }
    const res = await fetch(`${supabaseUrl}/rest/v1/api_call_cost_log`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'apikey': serviceRoleKey,
        'Authorization': `Bearer ${serviceRoleKey}`,
        'Prefer': 'return=minimal'
      },
      body: JSON.stringify({
        user_id: row.userId,
        function_name: row.functionName,
        model: row.model,
        prompt_tokens: row.promptTokens,
        completion_tokens: row.completionTokens,
        input_rate_per_million: row.inputRatePerMillion,
        output_rate_per_million: row.outputRatePerMillion,
        cost_usd: row.costUsd,
        cached_tokens: row.cachedTokens,
        surface: row.surface
      })
    });
    if (!res.ok) {
      console.error('logCallCost: insert failed', res.status, await res.text());
    }
  } catch (e) {
    console.error('logCallCost: unexpected error', e);
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const { systemPrompt, userMessage, temperature, forceJsonObject, model, surface } = await req.json();
    const resolvedSurface = typeof surface === 'string' && surface.trim() !== '' ? surface.trim().slice(0, 64) : null;

    if (!userMessage || typeof userMessage !== 'string') {
      return new Response(JSON.stringify({ error: 'userMessage is required' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    const apiKey = Deno.env.get('OPENAI_API_KEY');
    if (!apiKey) {
      return new Response(JSON.stringify({ error: 'OPENAI_API_KEY not configured' }), {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    // Whitelisted so a caller can never point this proxy at an arbitrary
    // OpenAI model string. Default stays 'gpt-4o' unless the caller opts
    // into 'gpt-4o-mini' (used for the 2026-08-11 side-by-side quality/speed
    // trial — see CLAUDE.md roadmap item 5).
    const allowedModels = ['gpt-4o', 'gpt-4o-mini'];
    const resolvedModel = typeof model === 'string' && allowedModels.includes(model) ? model : 'gpt-4o';

    const payload: Record<string, unknown> = {
      model: resolvedModel,
      messages: [
        { role: 'system', content: systemPrompt ?? '' },
        { role: 'user', content: userMessage }
      ],
      temperature: typeof temperature === 'number' ? temperature : 0.6,
      max_tokens: 1200,
      ...(forceJsonObject ? { response_format: { type: 'json_object' } } : {})
    };

    const openaiRes = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`
      },
      body: JSON.stringify(payload)
    });

    if (!openaiRes.ok) {
      const errText = await openaiRes.text();
      console.error('ask-chef-harris: OpenAI error', openaiRes.status, errText);
      return new Response(JSON.stringify({ error: 'Upstream AI request failed' }), {
        status: 502,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' }
      });
    }

    const data = await openaiRes.json();
    const content = data?.choices?.[0]?.message?.content ?? '';
    const usage = data?.usage ?? null;

    // Real token counts from OpenAI (not a char-count estimate) — logged
    // server-side (ephemeral, console only) so `supabase functions logs
    // ask-chef-harris` shows actual per-call cost, forwarded to the client
    // so ChefService can log it too, AND persisted durably in
    // api_call_cost_log (CLAUDE.md roadmap item 11 follow-up, 2026-08-13)
    // since neither of the first two survive past the log-retention window
    // or the browser tab closing.
    if (usage) {
      const rates = OPENAI_PRICING_PER_MILLION_TOKENS[resolvedModel] ?? OPENAI_PRICING_PER_MILLION_TOKENS['gpt-4o'];
      const promptTokens = usage.prompt_tokens ?? 0;
      const completionTokens = usage.completion_tokens ?? 0;
      // Prompt-caching investigation (2026-08-18): OpenAI reports how much
      // of prompt_tokens was served from its automatic prefix cache here.
      // Undefined on an older/non-caching-aware response shape — normalized
      // to null (not 0) so a row this field is genuinely missing from is
      // never confused with a row that measured a real zero.
      const cachedTokens = usage.prompt_tokens_details?.cached_tokens ?? null;
      // Cached prompt tokens bill at half rate, so they are priced
      // separately from the uncached remainder (2026-08-21). A null
      // cachedTokens means "not measured", which is treated as zero cached
      // here — that keeps the old, conservative (higher) cost for rows we
      // genuinely cannot verify, rather than inventing a discount.
      const billableCachedTokens = cachedTokens ?? 0;
      const uncachedPromptTokens = Math.max(0, promptTokens - billableCachedTokens);
      const estCostUsd =
        (uncachedPromptTokens / 1_000_000) * rates.input +
        (billableCachedTokens / 1_000_000) * rates.cachedInput +
        (completionTokens / 1_000_000) * rates.output;
      console.log(
        `ask-chef-harris: surface=${resolvedSurface ?? 'unset'} model=${resolvedModel} prompt_tokens=${promptTokens} cached_tokens=${cachedTokens} completion_tokens=${completionTokens} est_cost_usd=${estCostUsd.toFixed(5)}`
      );

      const userId = decodeUserIdFromAuthHeader(req.headers.get('Authorization'));
      // Awaited (not fire-and-forget-without-waiting) so the insert reliably
      // happens before the function instance tears down — this is a single
      // fast PostgREST call, and the try/catch inside logCallCost means a
      // failure here never turns into a 500 for the actual recipe response.
      await logCallCost({
        userId,
        functionName: 'ask-chef-harris',
        model: resolvedModel,
        promptTokens,
        completionTokens,
        inputRatePerMillion: rates.input,
        outputRatePerMillion: rates.output,
        costUsd: estCostUsd,
        cachedTokens,
        surface: resolvedSurface
      });
    }

    return new Response(JSON.stringify({ content, usage, model: resolvedModel }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  } catch (e) {
    console.error('ask-chef-harris: error', e);
    return new Response(JSON.stringify({ error: 'Internal error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' }
    });
  }
});
