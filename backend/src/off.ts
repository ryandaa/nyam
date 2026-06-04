/**
 * Open Food Facts barcode lookup.
 *
 * OFF is a free, open-source nutrition database (~3M packaged products
 * worldwide). No API key required, no rate limit at our volume. Cal AI
 * has no barcode mode — they're photo-only — so this is a real V5.1
 * differentiator for packaged-food tracking.
 *
 * API docs: https://wiki.openfoodfacts.org/API/Read
 * Product URL: https://world.openfoodfacts.org/api/v2/product/<barcode>.json
 */

import type { ScanItem, ScanTotals } from "./types";

const OFF_BASE = "https://world.openfoodfacts.org/api/v2";

export interface BarcodeProduct {
  name: string;
  brand: string | null;
  image_url: string | null;
  /// Grams per serving as the manufacturer reports it. May be null when
  /// OFF only has per-100g data; the caller falls back to scaling per-100g.
  serving_size_g: number | null;
  /// Nutrition for one serving (or per 100 g if serving_size_g is null).
  nutrition: ScanTotals;
}

export interface BarcodeLookupResult {
  found: boolean;
  barcode: string;
  product: BarcodeProduct | null;
  /// Diagnostic when not found.
  reason?: string;
}

interface OFFProductResponse {
  status: number; // 1 if found, 0 if not
  status_verbose?: string;
  product?: {
    product_name?: string;
    brands?: string;
    image_url?: string;
    image_small_url?: string;
    serving_size?: string;        // e.g. "30 g" or "1 cup (30 g)"
    nutriments?: {
      "energy-kcal_serving"?: number;
      "energy-kcal_100g"?: number;
      "proteins_serving"?: number;
      "proteins_100g"?: number;
      "carbohydrates_serving"?: number;
      "carbohydrates_100g"?: number;
      "fat_serving"?: number;
      "fat_100g"?: number;
      "fiber_serving"?: number;
      "fiber_100g"?: number;
      "sodium_serving"?: number;   // grams of sodium per serving
      "sodium_100g"?: number;
      "salt_serving"?: number;     // some products report salt instead
      "salt_100g"?: number;
    };
  };
}

/// Pull `<number> g` out of strings like "30 g", "1 cup (30 g)", "30g".
function parseServingGrams(raw: string | undefined): number | null {
  if (!raw) return null;
  const m = raw.match(/(\d+(?:\.\d+)?)\s*g/i);
  if (!m) return null;
  const v = Number(m[1]);
  return Number.isFinite(v) && v > 0 ? v : null;
}

/// Pick the serving-level value first, then fall back to per-100g.
function pick(
  perServing: number | undefined,
  per100g: number | undefined,
  servingG: number | null,
): number {
  if (typeof perServing === "number" && Number.isFinite(perServing)) return perServing;
  if (typeof per100g === "number" && Number.isFinite(per100g) && servingG) {
    return per100g * (servingG / 100);
  }
  // No serving size known — return per-100g as the "default serving."
  if (typeof per100g === "number" && Number.isFinite(per100g)) return per100g;
  return 0;
}

export async function lookupBarcode(barcode: string): Promise<BarcodeLookupResult> {
  const clean = barcode.replace(/\D/g, "");
  if (!clean) {
    return { found: false, barcode, product: null, reason: "Invalid barcode" };
  }

  let res: Response;
  try {
    res = await fetch(`${OFF_BASE}/product/${clean}.json`, {
      headers: { "User-Agent": "nyam/1.0 (https://github.com/ryandaa/nyam)" },
    });
  } catch (err) {
    return {
      found: false,
      barcode: clean,
      product: null,
      reason: err instanceof Error ? err.message : "Network error",
    };
  }
  if (!res.ok) {
    return { found: false, barcode: clean, product: null, reason: `OFF HTTP ${res.status}` };
  }

  const data = (await res.json()) as OFFProductResponse;
  if (data.status !== 1 || !data.product) {
    return {
      found: false,
      barcode: clean,
      product: null,
      reason: data.status_verbose ?? "Product not in Open Food Facts",
    };
  }

  const p = data.product;
  const n = p.nutriments ?? {};
  const servingG = parseServingGrams(p.serving_size);

  // OFF reports sodium in GRAMS — convert to mg. Some products list `salt`
  // instead of `sodium`; salt(g) × 0.4 = sodium(g).
  const sodiumG = pick(n["sodium_serving"], n["sodium_100g"], servingG);
  const saltG   = pick(n["salt_serving"],   n["salt_100g"],   servingG);
  const sodiumFinalMg = sodiumG > 0 ? sodiumG * 1000 : saltG * 0.4 * 1000;

  const nutrition: ScanTotals = {
    calories: round(pick(n["energy-kcal_serving"], n["energy-kcal_100g"], servingG), 0),
    protein_g: round(pick(n["proteins_serving"], n["proteins_100g"], servingG), 1),
    carbs_g:   round(pick(n["carbohydrates_serving"], n["carbohydrates_100g"], servingG), 1),
    fat_g:     round(pick(n["fat_serving"], n["fat_100g"], servingG), 1),
    fiber_g:   round(pick(n["fiber_serving"], n["fiber_100g"], servingG), 1),
    sodium_mg: Math.round(sodiumFinalMg),
  };

  return {
    found: true,
    barcode: clean,
    product: {
      name: p.product_name?.trim() || "Unknown product",
      brand: p.brands?.split(",")[0]?.trim() || null,
      image_url: p.image_small_url ?? p.image_url ?? null,
      serving_size_g: servingG,
      nutrition,
    },
  };
}

function round(value: number, places: number): number {
  const m = Math.pow(10, places);
  return Math.round(value * m) / m;
}

/// Build a one-item ScanItem from a barcode product, scaled by the number of
/// servings the user actually ate (typically a 0.25-step user-selected value).
export function barcodeProductAsScanItem(
  product: BarcodeProduct,
  servings: number,
): ScanItem {
  const factor = servings;
  return {
    name: [product.brand, product.name].filter(Boolean).join(" — ") || product.name,
    plate_area_percent: 0,
    width_cm: 0, depth_cm: 0, height_cm: 0,
    estimated_grams: product.serving_size_g ? round(product.serving_size_g * factor, 0) : 0,
    calories: round(product.nutrition.calories * factor, 0),
    protein_g: round(product.nutrition.protein_g * factor, 1),
    carbs_g: round(product.nutrition.carbs_g * factor, 1),
    fat_g: round(product.nutrition.fat_g * factor, 1),
    fiber_g: round(product.nutrition.fiber_g * factor, 1),
    sodium_mg: Math.round(product.nutrition.sodium_mg * factor),
    nutrition_source: "open_food_facts",
  };
}
