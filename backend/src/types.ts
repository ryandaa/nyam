export interface Env {
  OPENAI_API_KEY: string;
  APPLE_AUDIENCE: string;
  /// USDA FoodData Central API key. Optional — if missing, we fall back to
  /// the model's macro estimates without USDA grounding.
  USDA_API_KEY?: string;
}

export interface ScanRequest {
  image_base64: string;
  /// Optional: when present (ARKit measured the plate live), the prompt
  /// anchors every gram estimate to this real-world plate area. When
  /// absent (library photo, AR couldn't lock), the model falls back to
  /// unanchored portion estimation from context clues.
  plate_diameter_cm?: number;
  /// Optional: real food volume measured via LiDAR depth (Pro iPhones only).
  /// Only meaningful when plate_diameter_cm is also present.
  food_volume_cm3?: number;
}

export interface ChatRequest {
  messages: { role: "user" | "assistant"; content: string }[];
  history_summary: {
    title: string;
    date: string;
    calories: number;
    protein_g: number;
    carbs_g: number;
    fat_g: number;
    fiber_g: number;
    sodium_mg: number;
    items: string[];
  }[];
}

export type NutritionSource = "usda" | "model" | "manual" | "open_food_facts";

export interface ScanItem {
  name: string;
  plate_area_percent: number;
  width_cm: number;
  depth_cm: number;
  height_cm: number;
  estimated_grams: number;
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  fiber_g: number;
  sodium_mg: number;
  /// Where these macros came from. "usda" = scaled from FoodData Central,
  /// "model" = model's own estimate (USDA had no good match). Added
  /// post-OpenAI by the Worker, NOT produced by the model.
  nutrition_source?: NutritionSource;
  /// USDA FoodData Central food id, for citation when nutrition_source = "usda".
  usda_fdc_id?: number;
  /// USDA's canonical name for the matched food.
  usda_description?: string;
}

export interface ScanTotals {
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  fiber_g: number;
  sodium_mg: number;
}

export interface ScanResult {
  plate_detected: boolean;
  title: string;
  items: ScanItem[];
  totals: ScanTotals;
}
