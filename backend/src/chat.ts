/**
 * AI dietitian chat. Takes the user's recent meal history + the running
 * conversation transcript and asks GPT-4o-mini (cheap, fast, ~2s response)
 * to act as a friendly RD-style assistant.
 *
 * What this is NOT:
 * - A medical diagnosis tool. The system prompt explicitly forbids it.
 * - Persistent memory. Each request sends the full conversation; no
 *   server-side state.
 *
 * Cal AI doesn't have anything like this — they ship one-way nutrition
 * estimates. The chat is one of Nyam's biggest product-surface differentiators.
 */

const SYSTEM_PROMPT = `You are the user's personal AI dietitian. You help them understand their eating patterns based on the meals they have logged.

IDENTITY
- Refer to yourself as "your personal AI dietitian" if you mention what you are. Do not call yourself a "Nyam coach" or refer to the Nyam app.
- Speak directly to the user. First person ("I noticed…") and second person ("your protein has been…") only.

GROUND RULES
- Be specific. Cite meals from their log by title and day when relevant.
- Use round numbers (e.g. "around 1,800 cal", not "1,847.3 cal").
- Keep responses short by default — 2-4 sentences unless they ask for more detail.
- Don't moralize. No "you should" preaching. Observations, not commandments.
- Don't diagnose. If asked about medical conditions, suggest they talk to a doctor or RD.
- If they ask about something not in their log, say so honestly: "I don't see that in your scans this week."
- Use plain English, not jargon. No "macronutrient distribution" — say "your protein vs carbs vs fat."

STYLE
- Warm and brief. Slightly conversational, not corporate.
- If the user is doing well on a metric, say so. If a pattern looks off, point it out gently with what you saw.`;

interface HistoryEntrySummary {
  title: string;
  date: string;          // ISO date or relative
  calories: number;
  protein_g: number;
  carbs_g: number;
  fat_g: number;
  fiber_g: number;
  sodium_mg: number;
  items: string[];       // top item names
}

export interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

interface OpenAIChatResponse {
  choices?: Array<{ message?: { content?: string } }>;
  error?: { message?: string; type?: string };
}

export async function chatWithCoach(
  messages: ChatMessage[],
  history: HistoryEntrySummary[],
  apiKey: string,
): Promise<string> {
  // Compact the history into a single system-like context message.
  // GPT-4o-mini handles this well; we don't need to embed all the meal data
  // in the system prompt itself.
  const historyContext = formatHistory(history);
  const fullMessages = [
    { role: "system", content: SYSTEM_PROMPT },
    { role: "system", content: historyContext },
    ...messages.map((m) => ({ role: m.role, content: m.content })),
  ];

  const body = {
    model: "gpt-4o-mini",
    messages: fullMessages,
    temperature: 0.6,
    max_tokens: 350,
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
    throw new Error(data.error?.message ?? `OpenAI chat failed (${res.status})`);
  }
  const reply = data.choices?.[0]?.message?.content?.trim();
  if (!reply) {
    throw new Error("OpenAI returned an empty assistant message");
  }
  return reply;
}

function formatHistory(history: HistoryEntrySummary[]): string {
  if (history.length === 0) {
    return "USER MEAL LOG: (no meals logged yet — be encouraging and short)";
  }
  const lines = history.map((entry, i) => {
    const items = entry.items.length ? ` (${entry.items.slice(0, 4).join(", ")})` : "";
    return `${i + 1}. ${entry.date} — ${entry.title}${items}: ${Math.round(entry.calories)} kcal, ${Math.round(entry.protein_g)}g P, ${Math.round(entry.carbs_g)}g C, ${Math.round(entry.fat_g)}g F, ${Math.round(entry.fiber_g)}g fiber, ${Math.round(entry.sodium_mg)}mg sodium`;
  });
  return `USER MEAL LOG (newest first, last ${history.length} entries):\n${lines.join("\n")}`;
}
