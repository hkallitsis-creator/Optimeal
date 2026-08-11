import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const { systemPrompt, userMessage, temperature, forceJsonObject, model } = await req.json();

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

    return new Response(JSON.stringify({ content }), {
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
