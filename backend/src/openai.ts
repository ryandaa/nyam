import { SCAN_SCHEMA } from "./schema";
import type { ScanResult } from "./types";

const SYSTEM_PROMPT = `You are a nutrition vision model. You analyze overhead photos of meals on plates and return strict JSON nutrition estimates.

THE CRITICAL ANCHOR — THE PLATE IS YOUR SCALE
The user supplies the plate's real-world diameter in centimeters. Compute the plate's total area: A_plate = π × (diameter / 2)². Every portion estimate must be derived from this anchor — do NOT free-form-guess sizes the way an unanchored vision model would. The plate is the only ground-truth measurement you have.

REASONING STEPS (think through these silently, then emit JSON)
1. Confirm a plate is visible. If not, plate_detected=false and items=[].
2. Identify each distinct food item. Merge items of the same kind (one "rice", not three). Aim for 2–6 items per plate unless clearly more.
3. For each item, estimate footprint as a percent of the plate's circular area (plate_area_percent, 0–100).
4. Compute the item's footprint area in cm² from plate_area_percent and the plate area.
5. Estimate the item's average height in cm (this is the hardest step — be conservative):
     - flat foods (sauce, leafy greens, deli slices): 0.5–1 cm
     - typical sides (rice, pasta, beans, vegetables): 1.5–3 cm
     - dense piles / proteins (chicken thigh, steak, fish fillet): 2–4 cm
     - heaped mounds, burgers, stacks: 4–6 cm
6. Estimate volume = area × height in cm³.
7. Convert to grams using a typical density:
     - cooked grains (rice, pasta, quinoa): ~0.7 g/cm³
     - cooked proteins (chicken, fish, beef): ~1.0 g/cm³
     - cooked vegetables: ~0.6 g/cm³
     - bread / baked goods: ~0.3 g/cm³
     - sauces, dressings: ~1.0 g/cm³
     - leafy greens / salads: ~0.3 g/cm³
8. From grams, look up macros per 100 g for that specific food (use standard nutrition references — USDA-style values). Compute calories, protein_g, carbs_g, fat_g.
9. Sanity-check: per-item plate_area_percent values should roughly sum to ≤ 100 (empty plate space is normal). Totals must equal the sum of per-item macros.

RULES
- Only count what is clearly visible. Do not invent items.
- When food is layered or partially hidden, lower your estimate rather than guess high.
- Round grams to the nearest 5 g; round calories to the nearest 5 kcal; round macros to one decimal.
- Item names: lowercase common English, no brand names unless they are unmistakable (e.g. "grilled chicken thigh", "white jasmine rice", "steamed broccoli", "fried egg").
- Return JSON exactly matching the supplied schema. No prose, no markdown, no trailing text.`;

interface OpenAIChatResponse {
  choices?: Array<{
    message?: { content?: string };
  }>;
  error?: { message?: string; type?: string };
}

export async function analyzePlate(
  imageBase64: string,
  plateDiameterCm: number,
  apiKey: string,
): Promise<ScanResult> {
  const plateAreaCm2 = Math.PI * Math.pow(plateDiameterCm / 2, 2);
  const userText =
    `Plate diameter: ${plateDiameterCm.toFixed(1)} cm ` +
    `(plate area ≈ ${plateAreaCm2.toFixed(0)} cm²). ` +
    `Identify every visible food item and return the structured nutrition result. ` +
    `Anchor every gram estimate to this plate area.`;

  const body = {
    model: "gpt-4o-2024-08-06",
    messages: [
      { role: "system", content: SYSTEM_PROMPT },
      {
        role: "user",
        content: [
          { type: "text", text: userText },
          {
            type: "image_url",
            image_url: {
              url: `data:image/jpeg;base64,${imageBase64}`,
              detail: "high",
            },
          },
        ],
      },
    ],
    response_format: {
      type: "json_schema",
      json_schema: SCAN_SCHEMA,
    },
    temperature: 0.2,
  };

  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(body),
  });

  const data = (await res.json()) as OpenAIChatResponse;

  if (!res.ok) {
    const msg = data.error?.message ?? `OpenAI request failed (${res.status})`;
    throw new Error(msg);
  }

  const content = data.choices?.[0]?.message?.content;
  if (!content) {
    throw new Error("OpenAI returned no content");
  }

  // With strict json_schema, content is a JSON string matching SCAN_SCHEMA.
  return JSON.parse(content) as ScanResult;
}
