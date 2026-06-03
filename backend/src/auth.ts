/**
 * Verifies an Apple "Sign in with Apple" identity token.
 *
 * Apple identity tokens are RS256-signed JWTs. We fetch the JWKS from
 * appleid.apple.com, find the key matching the token's `kid`, and verify the
 * signature with Web Crypto (available in Workers). We then validate:
 *   - iss === "https://appleid.apple.com"
 *   - aud === the configured audience (your iOS bundle id)
 *   - exp > now
 *
 * Returns the validated claims on success, throws on failure.
 *
 * JWKS is cached in module scope per Worker instance. Apple rotates keys
 * occasionally; on a verification miss we refetch.
 */

const APPLE_ISS = "https://appleid.apple.com";
const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";

interface AppleJWK {
  kty: "RSA";
  kid: string;
  use: string;
  alg: "RS256";
  n: string;
  e: string;
}

interface AppleJWKS {
  keys: AppleJWK[];
}

export interface AppleClaims {
  iss: string;
  aud: string;
  exp: number;
  iat: number;
  sub: string;
  email?: string;
}

let cachedJWKS: AppleJWKS | null = null;
let cachedAt = 0;
const JWKS_TTL_MS = 60 * 60 * 1000; // 1 hour

async function fetchJWKS(): Promise<AppleJWKS> {
  const now = Date.now();
  if (cachedJWKS && now - cachedAt < JWKS_TTL_MS) {
    return cachedJWKS;
  }
  const res = await fetch(APPLE_JWKS_URL);
  if (!res.ok) {
    throw new Error(`Failed to fetch Apple JWKS: ${res.status}`);
  }
  cachedJWKS = (await res.json()) as AppleJWKS;
  cachedAt = now;
  return cachedJWKS;
}

function base64UrlDecode(input: string): Uint8Array {
  // base64url → base64
  const b64 = input.replace(/-/g, "+").replace(/_/g, "/").padEnd(input.length + ((4 - (input.length % 4)) % 4), "=");
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function base64UrlDecodeToString(input: string): string {
  return new TextDecoder().decode(base64UrlDecode(input));
}

async function importApplePublicKey(jwk: AppleJWK): Promise<CryptoKey> {
  return crypto.subtle.importKey(
    "jwk",
    {
      kty: jwk.kty,
      n: jwk.n,
      e: jwk.e,
      alg: "RS256",
      ext: true,
    },
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"],
  );
}

export async function verifyAppleIdentityToken(
  token: string,
  expectedAudience: string,
): Promise<AppleClaims> {
  const parts = token.split(".");
  if (parts.length !== 3) {
    throw new Error("Malformed JWT");
  }
  const [headerB64, payloadB64, signatureB64] = parts;

  const header = JSON.parse(base64UrlDecodeToString(headerB64)) as { kid: string; alg: string };
  if (header.alg !== "RS256") {
    throw new Error(`Unexpected JWT alg: ${header.alg}`);
  }

  const jwks = await fetchJWKS();
  let key = jwks.keys.find((k) => k.kid === header.kid);
  if (!key) {
    // Apple may have rotated; bust cache and retry once.
    cachedJWKS = null;
    const fresh = await fetchJWKS();
    key = fresh.keys.find((k) => k.kid === header.kid);
    if (!key) {
      throw new Error(`No matching Apple JWKS key for kid ${header.kid}`);
    }
  }

  const publicKey = await importApplePublicKey(key);
  const signedData = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
  const signature = base64UrlDecode(signatureB64);

  const valid = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    publicKey,
    signature,
    signedData,
  );
  if (!valid) {
    throw new Error("Apple JWT signature verification failed");
  }

  const claims = JSON.parse(base64UrlDecodeToString(payloadB64)) as AppleClaims;

  if (claims.iss !== APPLE_ISS) {
    throw new Error(`Unexpected iss: ${claims.iss}`);
  }
  if (claims.aud !== expectedAudience) {
    throw new Error(`Unexpected aud: ${claims.aud} (expected ${expectedAudience})`);
  }
  const nowSec = Math.floor(Date.now() / 1000);
  if (claims.exp <= nowSec) {
    throw new Error("Apple JWT expired");
  }

  return claims;
}
