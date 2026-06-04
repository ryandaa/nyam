import { verifyAppleIdentityToken } from "./auth";
import { analyzePlate } from "./openai";
import { lookupFoods, scaleByGrams, lookupBarcodeUSDA } from "./usda";
import { chatWithCoach } from "./chat";
import { lookupBarcode } from "./off";
import { analyzeMenu } from "./menu";
import type { ChatRequest, Env, NutritionSource, ScanItem, ScanRequest, ScanResult } from "./types";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS, GET",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Max-Age": "86400",
};

function json(body: unknown, status = 200, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...CORS_HEADERS,
      ...extra,
    },
  });
}

function bearer(req: Request): string | null {
  const header = req.headers.get("Authorization") ?? req.headers.get("authorization");
  if (!header) return null;
  const m = header.match(/^Bearer\s+(.+)$/i);
  return m ? m[1] : null;
}

/**
 * For each item the model identified, try to enrich its macros from USDA
 * FoodData Central. If USDA returns a match, scale per-100g nutrition by
 * the model's gram estimate and replace the model's macros. Otherwise leave
 * the item untouched. Sets nutrition_source so the iOS UI can show
 * provenance per item.
 */
async function enrichWithUSDA(result: ScanResult, apiKey: string | undefined): Promise<ScanResult> {
  if (!apiKey || result.items.length === 0) {
    return {
      ...result,
      items: result.items.map((it) => ({ ...it, nutrition_source: "model" as NutritionSource })),
    };
  }

  const lookups = await lookupFoods(result.items.map((it) => it.name), apiKey);
  const enrichedItems: ScanItem[] = result.items.map((item) => {
    const usda = lookups.get(item.name);
    if (!usda) {
      return { ...item, nutrition_source: "model" as NutritionSource };
    }
    const scaled = scaleByGrams(usda, item.estimated_grams);

    // Atwater fallback. USDA's FoodData Central sometimes has nutrient gaps
    // — a record might list protein/fat/sodium but omit the energy_kcal
    // (nutrient 1008) value. Without this fallback, those records would
    // come back as "0 kcal" which is obviously wrong. Atwater general
    // factors (4/4/9 kcal per g protein/carbs/fat) is the standard
    // food-science fill-in and what USDA itself uses internally.
    if (scaled.calories === 0) {
      const atwater = scaled.protein_g * 4 + scaled.carbs_g * 4 + scaled.fat_g * 9;
      if (atwater >= 5) {
        scaled.calories = Math.round(atwater);
      } else {
        // USDA record is nearly all zeros — match quality is bad,
        // fall back to the model's macros for this item.
        return { ...item, nutrition_source: "model" as NutritionSource };
      }
    }

    return {
      ...item,
      calories: scaled.calories,
      protein_g: scaled.protein_g,
      carbs_g: scaled.carbs_g,
      fat_g: scaled.fat_g,
      fiber_g: scaled.fiber_g,
      sodium_mg: scaled.sodium_mg,
      nutrition_source: "usda" as NutritionSource,
      usda_fdc_id: usda.fdcId,
      usda_description: usda.description,
    };
  });

  // Recompute totals so they match the (possibly replaced) per-item macros.
  const totals = enrichedItems.reduce(
    (acc, it) => {
      acc.calories += it.calories;
      acc.protein_g += it.protein_g;
      acc.carbs_g += it.carbs_g;
      acc.fat_g += it.fat_g;
      acc.fiber_g += it.fiber_g;
      acc.sodium_mg += it.sodium_mg;
      return acc;
    },
    { calories: 0, protein_g: 0, carbs_g: 0, fat_g: 0, fiber_g: 0, sodium_mg: 0 },
  );

  return {
    ...result,
    items: enrichedItems,
    totals: {
      calories: Math.round(totals.calories),
      protein_g: round(totals.protein_g, 1),
      carbs_g: round(totals.carbs_g, 1),
      fat_g: round(totals.fat_g, 1),
      fiber_g: round(totals.fiber_g, 1),
      sodium_mg: Math.round(totals.sodium_mg),
    },
  };
}

function round(value: number, places: number): number {
  const m = Math.pow(10, places);
  return Math.round(value * m) / m;
}

async function handleBarcode(url: URL, env: Env): Promise<Response> {
  const parts = url.pathname.split("/");
  const code = parts[parts.length - 1];
  if (!code) {
    return json({ error: "Missing barcode in path" }, 400);
  }
  try {
    // 1) Open Food Facts — strongest for European packaged goods.
    const offResult = await lookupBarcode(code);
    if (offResult.found) {
      return json({ ...offResult, source: "open_food_facts" });
    }

    // 2) Fall back to USDA Branded — strongest for US protein shakes,
    //    supplements, and other US grocery products that OFF misses.
    if (env.USDA_API_KEY) {
      const usdaProduct = await lookupBarcodeUSDA(code, env.USDA_API_KEY);
      if (usdaProduct) {
        return json({
          found: true,
          barcode: code.replace(/\D/g, ""),
          product: {
            name: usdaProduct.name,
            brand: usdaProduct.brand,
            image_url: null,
            serving_size_g: usdaProduct.servingSizeG,
            nutrition: usdaProduct.nutrition,
          },
          source: "usda_branded",
        });
      }
    }

    // 3) Neither database has it. Surface a friendly reason.
    return json({
      ...offResult,
      reason: offResult.reason ?? "Not in Open Food Facts or USDA Branded Foods",
      source: "none",
    });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Barcode lookup failed";
    console.error("barcode error:", message);
    return json({ error: message }, 502);
  }
}

async function handleMenu(request: Request, env: Env, url: URL): Promise<Response> {
  const token = bearer(request);
  const skipAuth = url.searchParams.get("dev") === "1" && env.APPLE_AUDIENCE === "ai.gojuly.nyam";
  if (!token && !skipAuth) {
    return json({ error: "Missing Authorization: Bearer <appleIdentityToken>" }, 401);
  }
  if (token) {
    try {
      await verifyAppleIdentityToken(token, env.APPLE_AUDIENCE);
    } catch (err) {
      const message = err instanceof Error ? err.message : "Auth failed";
      if (!skipAuth) {
        return json({ error: `Auth failed: ${message}` }, 401);
      }
    }
  }

  let body: { image_base64?: string };
  try {
    body = (await request.json()) as { image_base64?: string };
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  if (!body.image_base64 || typeof body.image_base64 !== "string") {
    return json({ error: "image_base64 (string) required" }, 400);
  }
  if (!env.OPENAI_API_KEY) {
    return json({ error: "Server is missing OPENAI_API_KEY" }, 500);
  }

  try {
    const result = await analyzeMenu(body.image_base64, env.OPENAI_API_KEY);
    return json(result);
  } catch (err) {
    const message = err instanceof Error ? err.message : "Menu analysis failed";
    console.error("menu error:", message);
    return json({ error: message }, 502);
  }
}

async function handleChat(request: Request, env: Env, url: URL): Promise<Response> {
  // Same auth posture as /scan — Bearer token required unless ?dev=1.
  const token = bearer(request);
  const skipAuth = url.searchParams.get("dev") === "1" && env.APPLE_AUDIENCE === "ai.gojuly.nyam";
  if (!token && !skipAuth) {
    return json({ error: "Missing Authorization: Bearer <appleIdentityToken>" }, 401);
  }
  if (token) {
    try {
      await verifyAppleIdentityToken(token, env.APPLE_AUDIENCE);
    } catch (err) {
      const message = err instanceof Error ? err.message : "Auth failed";
      if (!skipAuth) {
        return json({ error: `Auth failed: ${message}` }, 401);
      }
    }
  }

  let body: ChatRequest;
  try {
    body = (await request.json()) as ChatRequest;
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  if (!Array.isArray(body.messages) || body.messages.length === 0) {
    return json({ error: "messages: non-empty array required" }, 400);
  }
  if (!Array.isArray(body.history_summary)) {
    return json({ error: "history_summary: array required (use [] if no history)" }, 400);
  }

  if (!env.OPENAI_API_KEY) {
    return json({ error: "Server is missing OPENAI_API_KEY" }, 500);
  }

  try {
    const reply = await chatWithCoach(body.messages, body.history_summary, env.OPENAI_API_KEY);
    return json({ reply });
  } catch (err) {
    const message = err instanceof Error ? err.message : "Chat failed";
    console.error("chat error:", message);
    return json({ error: message }, 502);
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    // Health check
    if (request.method === "GET" && url.pathname === "/") {
      return json({
        ok: true,
        service: "nyam-backend",
        usda_configured: Boolean(env.USDA_API_KEY),
      });
    }

    if (request.method === "POST" && url.pathname === "/chat") {
      return handleChat(request, env, url);
    }

    if (request.method === "POST" && url.pathname === "/menu") {
      return handleMenu(request, env, url);
    }

    // Barcode lookups are GET /barcode/<code>. No auth required — read-only
    // public data, no GPT spend. Worker tries Open Food Facts first then
    // falls back to USDA Branded if OFF doesn't have the product.
    if (request.method === "GET" && url.pathname.startsWith("/barcode/")) {
      return handleBarcode(url, env);
    }

    if (request.method !== "POST" || url.pathname !== "/scan") {
      return json({ error: "Not found" }, 404);
    }

    // Auth
    const token = bearer(request);
    const skipAuth = url.searchParams.get("dev") === "1" && env.APPLE_AUDIENCE === "ai.gojuly.nyam";
    if (!token && !skipAuth) {
      return json({ error: "Missing Authorization: Bearer <appleIdentityToken>" }, 401);
    }
    if (token) {
      try {
        await verifyAppleIdentityToken(token, env.APPLE_AUDIENCE);
      } catch (err) {
        const message = err instanceof Error ? err.message : "Auth failed";
        if (!skipAuth) {
          return json({ error: `Auth failed: ${message}` }, 401);
        }
      }
    }

    // Body
    let body: ScanRequest;
    try {
      body = (await request.json()) as ScanRequest;
    } catch {
      return json({ error: "Invalid JSON body" }, 400);
    }

    if (!body.image_base64 || typeof body.image_base64 !== "string") {
      return json({ error: "image_base64 (string) required" }, 400);
    }
    if (
      body.plate_diameter_cm !== undefined &&
      (typeof body.plate_diameter_cm !== "number" || body.plate_diameter_cm <= 0)
    ) {
      return json({ error: "plate_diameter_cm must be a positive number when provided" }, 400);
    }
    if (body.food_volume_cm3 !== undefined && (typeof body.food_volume_cm3 !== "number" || body.food_volume_cm3 < 0)) {
      return json({ error: "food_volume_cm3 must be a non-negative number when provided" }, 400);
    }

    if (!env.OPENAI_API_KEY) {
      return json({ error: "Server is missing OPENAI_API_KEY" }, 500);
    }

    try {
      const visionResult = await analyzePlate(
        body.image_base64,
        body.plate_diameter_cm,
        env.OPENAI_API_KEY,
        body.food_volume_cm3,
      );
      const enriched = await enrichWithUSDA(visionResult, env.USDA_API_KEY);
      return json(enriched);
    } catch (err) {
      const message = err instanceof Error ? err.message : "OpenAI call failed";
      console.error("scan error:", message);
      return json({ error: message }, 502);
    }
  },
};
