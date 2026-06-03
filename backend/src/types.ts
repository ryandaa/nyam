export interface Env {
  OPENAI_API_KEY: string;
  APPLE_AUDIENCE: string;
}

export interface ScanRequest {
  image_base64: string;
  plate_diameter_cm: number;
}

export interface ScanItem {
  name: string;
  plate_area_percent: number;
  estimated_grams: number;
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
}

export interface ScanTotals {
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
}

export interface ScanResult {
  plate_detected: boolean;
  items: ScanItem[];
  totals: ScanTotals;
}
