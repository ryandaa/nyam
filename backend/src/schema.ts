/**
 * JSON Schema for OpenAI structured outputs. Mirrors `ScanResult` in types.ts
 * and `ScanResult.swift` on the iOS side. `additionalProperties: false` and the
 * complete `required` arrays are mandatory for `response_format: json_schema`
 * with `strict: true`.
 */
export const SCAN_SCHEMA = {
  name: "ScanResult",
  strict: true,
  schema: {
    type: "object",
    additionalProperties: false,
    properties: {
      plate_detected: {
        type: "boolean",
        description: "True if a plate is visible in the photo.",
      },
      items: {
        type: "array",
        description: "One entry per distinct food item on the plate.",
        items: {
          type: "object",
          additionalProperties: false,
          properties: {
            name: { type: "string", description: "Common name of the food, e.g. 'grilled chicken thigh'." },
            plate_area_percent: {
              type: "number",
              description: "Percent of the plate's circular area this item occupies, 0–100.",
            },
            estimated_grams: {
              type: "number",
              description: "Estimated weight in grams, using the plate diameter as a scale reference and typical food densities.",
            },
            calories: { type: "number", description: "Kilocalories." },
            protein_g: { type: "number" },
            carbs_g: { type: "number" },
            fat_g: { type: "number" },
          },
          required: [
            "name",
            "plate_area_percent",
            "estimated_grams",
            "calories",
            "protein_g",
            "carbs_g",
            "fat_g",
          ],
        },
      },
      totals: {
        type: "object",
        additionalProperties: false,
        properties: {
          calories: { type: "number" },
          protein_g: { type: "number" },
          carbs_g: { type: "number" },
          fat_g: { type: "number" },
        },
        required: ["calories", "protein_g", "carbs_g", "fat_g"],
      },
    },
    required: ["plate_detected", "items", "totals"],
  },
} as const;
