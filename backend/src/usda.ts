/**
 * USDA FoodData Central lookup.
 *
 * After GPT-4o identifies food items and estimates grams, we hit USDA's
 * authoritative nutrition database for each item, pull the actual per-100g
 * values, and rescale by the model's grams estimate. This replaces the
 * model's macro guesses with US government data when a high-confidence
 * match exists; otherwise we fall back to the model's estimate.
 *
 * Cal AI's nutrition source is unnamed "open-source food calorie databases
 * from GitHub" (per TechCrunch, Mar 2025). Nyam's nutrition data is the
 * official FoodData Central database that USDA actively maintains.
 *
 * API: https://fdc.nal.usda.gov/api-guide.html
 * Free key: https://api.data.gov/signup/
 */

const FDC_BASE = "https://api.nal.usda.gov/fdc/v1";

// USDA nutrient IDs from FoodData Central. These are stable across food
// records, so we look up by id rather than name.
const NUTRIENT_ID = {
  energy_kcal: 1008,
  protein_g: 1003,
  carbs_g: 1005,
  fat_g: 1004,
  fiber_g: 1079,
  sodium_mg: 1093,
} as const;

export interface USDANutrition {
  /// Per 100 g of edible food.
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  fiber_g: number;
  sodium_mg: number;
  /// FDC food name (e.g. "Chicken, broilers or fryers, thigh, meat only, cooked, roasted")
  description: string;
  /// FoodData Central numeric id, for citation.
  fdcId: number;
  /// USDA data type: "SR Legacy" / "Foundation" / "Survey (FNDDS)" / "Branded".
  dataType: string;
}

interface FDCSearchHit {
  fdcId: number;
  description: string;
  dataType?: string;
  score?: number;
  foodNutrients?: Array<{
    nutrientId: number;
    nutrientName?: string;
    value: number;
    unitName?: string;
  }>;
}

interface FDCSearchResponse {
  foods?: FDCSearchHit[];
  totalHits?: number;
}

function pickValue(hit: FDCSearchHit, nutrientId: number): number {
  const n = hit.foodNutrients?.find((x) => x.nutrientId === nutrientId);
  return n?.value ?? 0;
}

/**
 * Look up nutrition for a single food name. Returns null on lookup failure
 * (network error, no match, etc.) so the caller can fall back to the model.
 *
 * Strategy: search the curated SR Legacy + Foundation + FNDDS data types
 * (the audited core of FDC) rather than the branded data. Branded products
 * are heavy on processed/restaurant items and tend to add noise for the
 * generic food names GPT-4o produces ("grilled chicken thigh", "white rice").
 */
export async function lookupFood(name: string, apiKey: string): Promise<USDANutrition | null> {
  if (!name || !apiKey) return null;

  const url = new URL(`${FDC_BASE}/foods/search`);
  url.searchParams.set("query", name);
  url.searchParams.set("dataType", "Foundation,SR Legacy,Survey (FNDDS)");
  url.searchParams.set("pageSize", "1");
  url.searchParams.set("sortBy", "dataType.keyword");
  url.searchParams.set("api_key", apiKey);

  let res: Response;
  try {
    res = await fetch(url.toString(), { method: "GET" });
  } catch (err) {
    console.warn(`USDA lookup network error for "${name}":`, err);
    return null;
  }

  if (!res.ok) {
    console.warn(`USDA lookup HTTP ${res.status} for "${name}"`);
    return null;
  }

  let data: FDCSearchResponse;
  try {
    data = (await res.json()) as FDCSearchResponse;
  } catch {
    return null;
  }

  const hit = data.foods?.[0];
  if (!hit) return null;

  return {
    calories: pickValue(hit, NUTRIENT_ID.energy_kcal),
    protein_g: pickValue(hit, NUTRIENT_ID.protein_g),
    carbs_g: pickValue(hit, NUTRIENT_ID.carbs_g),
    fat_g: pickValue(hit, NUTRIENT_ID.fat_g),
    fiber_g: pickValue(hit, NUTRIENT_ID.fiber_g),
    sodium_mg: pickValue(hit, NUTRIENT_ID.sodium_mg),
    description: hit.description,
    fdcId: hit.fdcId,
    dataType: hit.dataType ?? "unknown",
  };
}

/**
 * USDA Branded Foods lookup by UPC/EAN. Open Food Facts has weak coverage
 * of US protein shakes / supplements (Premier Protein, Muscle Milk, Fairlife
 * etc. all 404 in OFF); USDA Branded is much stronger here because US
 * manufacturers submit data directly to it.
 *
 * Returns a complete BarcodeProduct-shape payload so the Worker can return
 * the same shape regardless of which database resolved the barcode.
 */
export interface USDABrandedProduct {
  name: string;
  brand: string | null;
  servingSizeG: number | null;
  /// Per-serving (or per-100g if serving unknown) macros.
  nutrition: {
    calories: number;
    protein_g: number;
    carbs_g: number;
    fat_g: number;
    fiber_g: number;
    sodium_mg: number;
  };
  fdcId: number;
}

interface FDCBrandedHit {
  fdcId: number;
  description?: string;
  brandName?: string;
  brandOwner?: string;
  gtinUpc?: string;
  servingSize?: number;
  servingSizeUnit?: string;
  /// Per-serving nutrition pre-rolled by USDA — preferred when present.
  labelNutrients?: {
    calories?: { value?: number };
    fat?: { value?: number };
    saturatedFat?: { value?: number };
    transFat?: { value?: number };
    cholesterol?: { value?: number };
    sodium?: { value?: number };       // mg
    carbohydrates?: { value?: number };
    fiber?: { value?: number };
    sugars?: { value?: number };
    protein?: { value?: number };
  };
  /// Fallback: per-100g nutrients keyed by nutrient ID.
  foodNutrients?: Array<{
    nutrientId: number;
    value: number;
    unitName?: string;
  }>;
}

export async function lookupBarcodeUSDA(
  barcode: string,
  apiKey: string,
): Promise<USDABrandedProduct | null> {
  const clean = barcode.replace(/\D/g, "");
  if (!clean || !apiKey) return null;

  // USDA's search index treats the UPC as plain text. Asking for several
  // results so we can pick the exact gtinUpc match.
  const url = new URL(`${FDC_BASE}/foods/search`);
  url.searchParams.set("query", clean);
  url.searchParams.set("dataType", "Branded");
  url.searchParams.set("pageSize", "10");
  url.searchParams.set("api_key", apiKey);

  let res: Response;
  try {
    res = await fetch(url.toString(), { method: "GET" });
  } catch (err) {
    console.warn(`USDA branded barcode network error for "${clean}":`, err);
    return null;
  }
  if (!res.ok) {
    console.warn(`USDA branded barcode HTTP ${res.status} for "${clean}"`);
    return null;
  }

  let data: { foods?: FDCBrandedHit[] };
  try {
    data = (await res.json()) as { foods?: FDCBrandedHit[] };
  } catch {
    return null;
  }
  const hits = data.foods ?? [];
  // Prefer an exact UPC match; some USDA records also normalize to a
  // leading-zero variant or strip them, so check both forms.
  const upcNoZeros = clean.replace(/^0+/, "");
  const match = hits.find((h) => {
    if (!h.gtinUpc) return false;
    const stripped = h.gtinUpc.replace(/^0+/, "");
    return h.gtinUpc === clean || stripped === upcNoZeros;
  });
  if (!match) return null;

  const servingG = (match.servingSizeUnit?.toLowerCase() === "g") ? match.servingSize ?? null : null;

  // Prefer labelNutrients (per-serving) when present. Else fall back to
  // per-100g foodNutrients scaled by the serving size, or just per-100g.
  const label = match.labelNutrients;
  let nutrition: USDABrandedProduct["nutrition"];
  if (label && (label.calories?.value ?? 0) > 0) {
    nutrition = {
      calories: round(label.calories?.value ?? 0, 0),
      protein_g: round(label.protein?.value ?? 0, 1),
      carbs_g: round(label.carbohydrates?.value ?? 0, 1),
      fat_g: round(label.fat?.value ?? 0, 1),
      fiber_g: round(label.fiber?.value ?? 0, 1),
      sodium_mg: Math.round(label.sodium?.value ?? 0),
    };
  } else {
    const per100 = {
      calories: nutrientValue(match.foodNutrients, NUTRIENT_ID.energy_kcal),
      protein_g: nutrientValue(match.foodNutrients, NUTRIENT_ID.protein_g),
      carbs_g: nutrientValue(match.foodNutrients, NUTRIENT_ID.carbs_g),
      fat_g: nutrientValue(match.foodNutrients, NUTRIENT_ID.fat_g),
      fiber_g: nutrientValue(match.foodNutrients, NUTRIENT_ID.fiber_g),
      sodium_mg: nutrientValue(match.foodNutrients, NUTRIENT_ID.sodium_mg),
    };
    if (servingG) {
      const f = servingG / 100;
      nutrition = {
        calories: round(per100.calories * f, 0),
        protein_g: round(per100.protein_g * f, 1),
        carbs_g: round(per100.carbs_g * f, 1),
        fat_g: round(per100.fat_g * f, 1),
        fiber_g: round(per100.fiber_g * f, 1),
        sodium_mg: Math.round(per100.sodium_mg * f),
      };
    } else {
      nutrition = {
        calories: round(per100.calories, 0),
        protein_g: round(per100.protein_g, 1),
        carbs_g: round(per100.carbs_g, 1),
        fat_g: round(per100.fat_g, 1),
        fiber_g: round(per100.fiber_g, 1),
        sodium_mg: Math.round(per100.sodium_mg),
      };
    }
  }

  return {
    name: cleanName(match.description ?? "Unknown product"),
    brand: cleanName(match.brandName ?? match.brandOwner ?? "") || null,
    servingSizeG: servingG,
    nutrition,
    fdcId: match.fdcId,
  };
}

function nutrientValue(arr: FDCBrandedHit["foodNutrients"], id: number): number {
  const n = arr?.find((x) => x.nutrientId === id);
  return n?.value ?? 0;
}

function cleanName(raw: string): string {
  // USDA descriptions are ALL CAPS with comma-separated qualifiers
  // ("PROTEIN SHAKE, CHOCOLATE"). Title-case for nicer display.
  const t = raw.trim();
  if (!t) return "";
  return t
    .toLowerCase()
    .split(/(\s+|,)/)
    .map((part) => (/[a-z]/.test(part) ? part.charAt(0).toUpperCase() + part.slice(1) : part))
    .join("");
}

/**
 * Look up many foods in parallel. Returns a Map keyed by the original name.
 * Lookup failures map to null — caller decides whether to fall back.
 */
export async function lookupFoods(
  names: string[],
  apiKey: string,
): Promise<Map<string, USDANutrition | null>> {
  const unique = Array.from(new Set(names));
  const results = await Promise.all(
    unique.map(async (name) => [name, await lookupFood(name, apiKey)] as const),
  );
  return new Map(results);
}

/**
 * Scale USDA per-100g nutrition values by the model's gram estimate.
 * Returns an object matching ScanItem's nutrition fields.
 */
export function scaleByGrams(
  per100g: USDANutrition,
  grams: number,
): Pick<USDANutrition, "calories" | "protein_g" | "carbs_g" | "fat_g" | "fiber_g" | "sodium_mg"> {
  const factor = grams / 100;
  return {
    calories: round(per100g.calories * factor, 1),
    protein_g: round(per100g.protein_g * factor, 1),
    carbs_g: round(per100g.carbs_g * factor, 1),
    fat_g: round(per100g.fat_g * factor, 1),
    fiber_g: round(per100g.fiber_g * factor, 1),
    sodium_mg: round(per100g.sodium_mg * factor, 0),
  };
}

function round(value: number, places: number): number {
  const m = Math.pow(10, places);
  return Math.round(value * m) / m;
}
