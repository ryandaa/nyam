import { verifyAppleIdentityToken } from "./auth";
import { analyzePlate } from "./openai";
import { lookupFoods, scaleByGrams } from "./usda";
import type { Env, NutritionSource, ScanItem, ScanRequest, ScanResult } from "./types";

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
    if (typeof body.plate_diameter_cm !== "number" || body.plate_diameter_cm <= 0) {
      return json({ error: "plate_diameter_cm (positive number) required" }, 400);
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
