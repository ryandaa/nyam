import { verifyAppleIdentityToken } from "./auth";
import { analyzePlate } from "./openai";
import type { Env, ScanRequest } from "./types";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS, GET",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
  "Access-Control-Max-Age": "86400",
};

function json(body: unknown, status = 200, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...CORS_HEADERS,
      ...extra,
    },
  });
}

function bearer(req: Request): string | null {
  const header = req.headers.get("Authorization") ?? req.headers.get("authorization");
  if (!header) return null;
  const m = header.match(/^Bearer\s+(.+)$/i);
  return m ? m[1] : null;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    // Health check
    if (request.method === "GET" && url.pathname === "/") {
      return json({ ok: true, service: "nyam-backend" });
    }

    if (request.method !== "POST" || url.pathname !== "/scan") {
      return json({ error: "Not found" }, 404);
    }

    // Auth
    const token = bearer(request);
    const skipAuth = url.searchParams.get("dev") === "1" && env.APPLE_AUDIENCE === "ai.gojuly.nyam";
    if (!token && !skipAuth) {
      return json({ error: "Missing Authorization: Bearer <appleIdentityToken>" }, 401);
    }
    if (token) {
      try {
        await verifyAppleIdentityToken(token, env.APPLE_AUDIENCE);
      } catch (err) {
        const message = err instanceof Error ? err.message : "Auth failed";
        // In ?dev=1 mode we accept invalid tokens to ease local testing.
        if (!skipAuth) {
          return json({ error: `Auth failed: ${message}` }, 401);
        }
      }
    }

    // Body
    let body: ScanRequest;
    try {
      body = (await request.json()) as ScanRequest;
    } catch {
      return json({ error: "Invalid JSON body" }, 400);
    }

    if (!body.image_base64 || typeof body.image_base64 !== "string") {
      return json({ error: "image_base64 (string) required" }, 400);
    }
    if (typeof body.plate_diameter_cm !== "number" || body.plate_diameter_cm <= 0) {
      return json({ error: "plate_diameter_cm (positive number) required" }, 400);
    }

    if (!env.OPENAI_API_KEY) {
      return json({ error: "Server is missing OPENAI_API_KEY" }, 500);
    }

    try {
      const result = await analyzePlate(body.image_base64, body.plate_diameter_cm, env.OPENAI_API_KEY);
      return json(result);
    } catch (err) {
      const message = err instanceof Error ? err.message : "OpenAI call failed";
      console.error("scan error:", message);
      return json({ error: message }, 502);
    }
  },
};
