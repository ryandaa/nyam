import { SCAN_SCHEMA } from "./schema";
import type { ScanResult } from "./types";

const SYSTEM_PROMPT = `You analyze overhead photos of meals on plates.

A plate is visible in the image, and the user has told you its real-world diameter in centimeters. Use the plate as a scale reference: estimate each food item's footprint as a percentage of the plate's circular area, then convert to grams using typical food density and the plate's known area.

Rules:
- Only count visible items on the plate. Do not invent items you cannot see.
- If the plate is empty or no plate is visible, return an empty items array and plate_detected accordingly.
- Be conservative on grams when the food is layered or partially hidden — explain ambiguity by lowering your estimate.
- "totals" must equal the sum of per-item macros.
- Return JSON exactly matching the supplied schema.`;

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
  const userText = `Plate diameter: ${plateDiameterCm.toFixed(1)} cm. Identify every food item and return the structured result.`;

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
