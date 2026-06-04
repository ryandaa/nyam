/**
 * Menu vision analysis.
 *
 * GPT-4o reads a photo of a restaurant menu and returns a structured list of
 * dishes with per-serving nutrition estimates. Useful as a *pre-meal*
 * decision tool — see calories/macros before you order.
 *
 * Pairs with the plate-scan flow: scan a menu first, pick a dish, log it as
 * your meal. Cal AI is photo-of-food-only; menu inference is a real V5.1
 * differentiator.
 */

export const MENU_SCHEMA = {
  name: "MenuResult",
  strict: true,
  schema: {
    type: "object",
    additionalProperties: false,
    properties: {
      restaurant_name: {
        type: ["string", "null"],
        description: "Restaurant name if it appears on the menu (logo, header). Null if not visible.",
      },
      dishes: {
        type: "array",
        description: "One entry per distinct menu dish. 4–20 typical; cap at 25.",
        items: {
          type: "object",
          additionalProperties: false,
          properties: {
            name: { type: "string", description: "Dish name as printed on the menu." },
            description: {
              type: ["string", "null"],
              description: "Brief description if shown on the menu (under 100 chars). Null if absent.",
            },
            estimated_grams: {
              type: "number",
              description: "Estimated single-serving weight in grams, based on typical restaurant portion sizes.",
            },
            calories: { type: "number" },
            protein_g: { type: "number" },
            carbs_g: { type: "number" },
            fat_g: { type: "number" },
            fiber_g: { type: "number" },
            sodium_mg: { type: "number" },
          },
          required: [
            "name",
            "description",
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
    },
    required: ["restaurant_name", "dishes"],
  },
} as const;

export interface MenuDish {
  name: string;
  description: string | null;
  estimated_grams: number;
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  fiber_g: number;
  sodium_mg: number;
}

export interface MenuResult {
  restaurant_name: string | null;
  dishes: MenuDish[];
}

const SYSTEM_PROMPT = `You analyze photos of restaurant menus and return per-dish nutrition estimates.

THE TASK
You will be shown a photo of a printed or digital restaurant menu. Identify every distinct dish (entrées, sides, salads, desserts, drinks). For each, estimate calories and macros based on:
  1. The dish name and any description shown.
  2. Typical restaurant portion sizes (often 1.5–2× home portions).
  3. Standard food-science densities and USDA nutrient references for the cuisine.

RULES
- One entry per distinct dish. If the menu has "Pasta — Bolognese OR Carbonara OR Marinara", emit three separate entries.
- Skip section headers, prices, and modifiers. Only dishes.
- Cap at 25 dishes — if the menu has more, return the most prominent ones.
- Be honest about uncertainty: a 14-oz steak is ~1100 kcal restaurant-style; a side salad with vinaigrette is ~150–250 kcal.
- Round calories to nearest 5 kcal; macros to 1 decimal; sodium to 5 mg.
- restaurant_name: include only if it visibly appears on the menu (logo or header). Otherwise null.
- description: copy a short version of what the menu says (under 100 chars). If the menu shows no description, return null — don't invent one.
- Return JSON exactly matching the supplied schema.`;

interface OpenAIChatResponse {
  choices?: Array<{ message?: { content?: string } }>;
  error?: { message?: string; type?: string };
}

export async function analyzeMenu(
  imageBase64: string,
  apiKey: string,
): Promise<MenuResult> {
  const body = {
    model: "gpt-4o-2024-08-06",
    messages: [
      { role: "system", content: SYSTEM_PROMPT },
      {
        role: "user",
        content: [
          { type: "text", text: "Analyze this restaurant menu and return per-dish nutrition estimates." },
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
      json_schema: MENU_SCHEMA,
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
    const msg = data.error?.message ?? `OpenAI menu request failed (${res.status})`;
    throw new Error(msg);
  }
  const content = data.choices?.[0]?.message?.content;
  if (!content) {
    throw new Error("OpenAI returned no menu content");
  }
  return JSON.parse(content) as MenuResult;
}
