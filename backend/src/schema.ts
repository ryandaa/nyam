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
      title: {
        type: "string",
        description: "Short title for the meal, strictly 5 words or fewer, title-cased. Examples: 'Sesame Chicken & Rice Bowl', 'Greek Salad with Salmon', 'Pancakes with Berries'. Use 'Empty Plate' if no food.",
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
            width_cm: {
              type: "number",
              description: "Estimated longest horizontal dimension of the item on the plate, in cm. Derived from the plate scale anchor.",
            },
            depth_cm: {
              type: "number",
              description: "Estimated horizontal dimension perpendicular to width_cm, in cm. Together with width_cm this is the item's footprint.",
            },
            height_cm: {
              type: "number",
              description: "Estimated average height of the item above the plate, in cm. This is the hardest field — be conservative.",
            },
            estimated_grams: {
              type: "number",
              description: "Estimated weight in grams. Derived from width × depth × height × density, anchored to the plate diameter.",
            },
            calories: { type: "number", description: "Kilocalories." },
            protein_g: { type: "number" },
            carbs_g: { type: "number" },
            fat_g: { type: "number" },
            fiber_g: { type: "number", description: "Dietary fiber in grams." },
            sodium_mg: { type: "number", description: "Sodium in milligrams." },
          },
          required: [
            "name",
            "plate_area_percent",
            "width_cm",
            "depth_cm",
            "height_cm",
            "estimated_grams",
            "calories",
            "protein_g",
            "carbs_g",
            "fat_g",
            "fiber_g",
            "sodium_mg",
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
          fiber_g: { type: "number" },
          sodium_mg: { type: "number" },
        },
        required: ["calories", "protein_g", "carbs_g", "fat_g", "fiber_g", "sodium_mg"],
      },
    },
    required: ["plate_detected", "title", "items", "totals"],
  },
} as const;
