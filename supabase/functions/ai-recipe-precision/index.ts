// supabase/functions/ai-recipe-precision/index.ts
//
// Deploy with: supabase functions deploy ai-recipe-precision
// Requires these secrets set first:
//   supabase secrets set OPENAI_API_KEY=sk-...
//
// Schema alignment fix: ai_precision_cache has 6 typed jsonb columns
// (heat_spec, salt_timing, knife_cut_spec, swiss_substitutes, base_ratios,
// acid_balance_note) instead of a single precision_data blob. This version
// writes to each column individually and reconstructs the flat response
// shape on read.

import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface PrecisionRequest {
  ingredients: string[];
  method?: string;
  protein?: string;
  cutStyle?: string;
}

// Flat shape returned to the client (unchanged from before, so no
// front-end changes needed) — now includes baseRatios.
interface PrecisionData {
  heatLevel: string;
  heatReason: string;
  knifeCutSpecMm: number;
  saltTiming: string;
  acidBalanceNote: string;
  substituteSwiss: string;
  baseRatios: string;
}

async function sha256(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// Table row -> flat client shape
function rowToPrecisionData(row: any): PrecisionData {
  return {
    heatLevel: row.heat_spec?.level ?? "",
    heatReason: row.heat_spec?.reason ?? "",
    knifeCutSpecMm: row.knife_cut_spec?.thicknessMm ?? 0,
    saltTiming: row.salt_timing?.timing ?? "",
    acidBalanceNote: row.acid_balance_note?.note ?? "",
    substituteSwiss: row.swiss_substitutes?.substitute ?? "",
    baseRatios: row.base_ratios?.note ?? "",
  };
}

// Flat LLM output -> real table columns
function precisionDataToColumns(p: PrecisionData) {
  return {
    heat_spec: { level: p.heatLevel, reason: p.heatReason },
    knife_cut_spec: { thicknessMm: p.knifeCutSpecMm },
    salt_timing: { timing: p.saltTiming },
    acid_balance_note: { note: p.acidBalanceNote },
    swiss_substitutes: { substitute: p.substituteSwiss },
    base_ratios: { note: p.baseRatios },
  };
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const body: PrecisionRequest = await req.json();
    const { ingredients, method = "", protein = "", cutStyle = "" } = body;

    if (!ingredients || ingredients.length === 0) {
      return new Response(
        JSON.stringify({ error: "ingredients array is required" }),
        { status: 400, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
      );
    }

    const cacheInput = JSON.stringify({
      ingredients: [...ingredients].sort(),
      method,
      protein,
      cutStyle,
    });
    const cacheKey = await sha256(cacheInput);

    // 1. Check cache first — select the real columns.
    const { data: cachedRow } = await supabase
      .from("ai_precision_cache")
      .select("heat_spec, salt_timing, knife_cut_spec, swiss_substitutes, base_ratios, acid_balance_note, hit_count")
      .eq("cache_key", cacheKey)
      .maybeSingle();

    if (cachedRow) {
      // Bump hit_count / last_used_at — best-effort, don't block the response on it.
      supabase
        .from("ai_precision_cache")
        .update({
          hit_count: (cachedRow.hit_count ?? 0) + 1,
          last_used_at: new Date().toISOString(),
        })
        .eq("cache_key", cacheKey)
        .then(({ error }) => {
          if (error) console.error("Cache stats update failed (non-fatal):", error);
        });

      return new Response(JSON.stringify(rowToPrecisionData(cachedRow)), {
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    // 2. Cache miss — call the LLM.
    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    if (!openaiKey) {
      throw new Error("OPENAI_API_KEY secret is not set");
    }

    const systemPrompt = `You are a precision culinary data generator. Given a list of ingredients, a cooking method, and optional protein/cut style, return ONLY a JSON object (no prose, no markdown fences) with this exact shape:
{
  "heatLevel": string,        // e.g. "medium-high"
  "heatReason": string,       // why this heat level, grounded in thermal mass / Maillard timing
  "knifeCutSpecMm": number,   // recommended cut thickness in mm, 0 if not applicable
  "saltTiming": string,       // when to salt and why
  "acidBalanceNote": string,  // acid/fat balancing tip
  "substituteSwiss": string,  // a Swiss-available ingredient substitute, empty string if none needed
  "baseRatios": string        // key ratio guidance for this dish (e.g. liquid:starch, fat:acid), empty string if not applicable
}
Be technical and specific — temperatures, timings, physical cues, ratios. No generic filler.`;

    const userPrompt = `Ingredients: ${ingredients.join(", ")}
Method: ${method || "unspecified"}
Protein: ${protein || "none"}
Cut style: ${cutStyle || "unspecified"}`;

    const llmResponse = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${openaiKey}`,
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: userPrompt },
        ],
        response_format: { type: "json_object" },
        temperature: 0.3,
      }),
    });

    if (!llmResponse.ok) {
      const errText = await llmResponse.text();
      throw new Error(`LLM call failed (${llmResponse.status}): ${errText}`);
    }

    const llmJson = await llmResponse.json();
    const precisionData: PrecisionData = JSON.parse(llmJson.choices[0].message.content);

    // 3. Write-through to cache (best-effort — don't fail the request if this fails).
    const { error: cacheWriteError } = await supabase
      .from("ai_precision_cache")
      .insert({
        cache_key: cacheKey,
        ...precisionDataToColumns(precisionData),
        hit_count: 0,
        last_used_at: new Date().toISOString(),
      });
    if (cacheWriteError) {
      console.error("Cache write failed (non-fatal):", cacheWriteError);
    }

    return new Response(JSON.stringify(precisionData), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("ai-recipe-precision error:", err);
    return new Response(
      JSON.stringify({ error: err instanceof Error ? err.message : String(err) }),
      { status: 500, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }
});