# Nyam — Plate-Referenced Calorie Tracking

> Take an overhead photo of your plate. Nyam uses the plate as a known-size reference to actually *measure* food portions — instead of free-form guessing like Cal-AI.

CS 153 Final Project — *The One-Person Frontier Lab*

---

## The problem

Cal-AI and other photo-based calorie trackers have a known accuracy problem: GPT-4o (and similar vision models) have no scale anchor in a food photo. They guess "looks like ~150g of rice" with no real reference, and they can be wildly wrong — sometimes 2–3× off. Nutrition experts repeatedly flag this.

## The insight

**Your plate is a known-size object that appears in almost every food photo.** Standard US dinner plates are 10–11 inches across. If we (a) detect the plate's pixel diameter on-device, (b) tell the vision model the plate's real-world diameter, and (c) ask it to estimate each food's footprint as a percentage of the plate's area, we get a real measurement instead of a guess.

That's Nyam.

## Architecture

```
iPhone (SwiftUI)
    └── Camera + Apple Vision framework
        │   - detect plate ellipse on-device
        │   - user confirms diameter (default 26 cm / 10 in)
        ▼
    Cloudflare Worker (TypeScript)
        │   - verifies Sign in with Apple JWT
        │   - calls OpenAI GPT-4o vision with structured output
        ▼
    Results: per-item grams + macros + plate area %
```

- **Native iOS app** (SwiftUI, iOS 17+): Sign in with Apple → camera scan → calibration confirm → results.
- **Cloudflare Worker** (TypeScript): thin proxy that keeps the OpenAI key off the device and verifies SIWA tokens.
- **OpenAI GPT-4o** with `response_format: json_schema` — structured nutrition output, no string parsing.

## Setup

### Prerequisites

- macOS with **Xcode 15+** (iOS 17 SDK)
- **Node 20+** and **npm**
- **Cloudflare account** (free tier is plenty) + `wrangler` CLI (`npm i -g wrangler`)
- **OpenAI API key** with `gpt-4o` access
- **Apple Developer account** (free tier works for personal-device testing) — required for Sign in with Apple
- An **iPhone** for testing (Pro recommended; LiDAR is a planned future feature)

### 1. Backend — Cloudflare Worker

```bash
cd backend
npm install

# Set local OpenAI key for `wrangler dev`
echo 'OPENAI_API_KEY=sk-...' > .dev.vars

# Run the Worker locally on http://localhost:8787
npx wrangler dev --ip 0.0.0.0
```

For production deploy:

```bash
npx wrangler secret put OPENAI_API_KEY   # paste your key
npx wrangler deploy
```

The deploy URL (something like `https://nyam-backend.<your-subdomain>.workers.dev`) goes into `Nyam/Services/NyamAPI.swift` as `baseURL`.

### 2. iOS app

```bash
# Generate the .xcodeproj from project.yml
xcodegen
open Nyam.xcodeproj
```

In Xcode:
1. Pick your Apple Developer team under **Signing & Capabilities**.
2. Plug in your iPhone, select it as the run destination.
3. Edit `Nyam/Services/NyamAPI.swift` → set `baseURL` to either your local Worker (use your Mac's LAN IP, e.g. `http://192.168.1.42:8787`) or your deployed Worker URL.
4. Build & Run (⌘R).

## How it works end-to-end

1. **Sign in with Apple** — one-tap auth, returns an identity token persisted in Keychain.
2. **Camera view** — `AVCaptureSession` with a live `VNDetectRectanglesRequest` (Apple Vision framework) finds the plate's ellipse in the frame and draws an overlay.
3. **Capture** — user taps shutter; we grab the still photo.
4. **Calibration sheet** — confirm or adjust the detected plate diameter (default 26 cm = 10 in).
5. **POST `/scan`** — image is base64-encoded and sent to the Worker with the diameter and the Apple identity token.
6. **Worker** — verifies the Apple JWT, then calls OpenAI GPT-4o with a vision message and `response_format: { type: "json_schema", json_schema: SCAN_SCHEMA }`. The schema forces a typed `ScanResult` — no string parsing.
7. **Results view** — per-item cards (name, plate area %, grams, kcal, P/C/F) and a totals card at the bottom.

## Evaluation

> *In-progress — populate this table from real measured meals before submission.*

We compare Nyam's portion estimates against ground-truth kitchen-scale weights, side-by-side with an unanchored GPT-4o baseline (no plate reference).

| Meal | Component | True g | Nyam g | Δ % | Baseline g | Baseline Δ % |
|---|---|---|---|---|---|---|
| TBD | TBD | TBD | TBD | TBD | TBD | TBD |

*Procedure:* weigh each component on a kitchen scale, photograph overhead at ~50 cm height, run through both Nyam and an unanchored prompt, log results.

## AI usage disclosure

Per the rubric's *Process, Integrity & Disclosure* section:

- **Claude (Claude Code with Opus 4.7)** — used to scaffold the project structure, write the initial SwiftUI views, the Cloudflare Worker, and this README. Architecture decisions were made via Q&A with the user before any code was written; the plan is committed in the repo history.
- **OpenAI GPT-4o** — used at runtime as the vision model that identifies food and estimates portion sizes. This is the core ML component of the product.
- **No code was forked from another project.** All Swift and TypeScript was written for this repo.

## Limitations and future work

- **Single overhead photo only** — partially hidden foods (layered dishes, bowls of soup with toppings) are still hard.
- **No food-log persistence** — V1 shows results once; planned next is a Cloudflare D1 store keyed by SIWA `sub`.
- **No daily targets or weight goals** — planned.
- **LiDAR depth-based volume** — only works on iPhone Pro models; planned as a side-view companion capture to estimate food height (the second view the project proposal mentions).
- **Confidence scores per item** — model can output them; we drop them from the UI in V1 to keep it simple.
- **Plate detection robustness** — Vision rectangle detection works well on round plates against contrasting tablecloths; rectangular plates and busy backgrounds degrade it.

## Repo layout

```
nyam/
├── README.md
├── project.yml            # xcodegen config — regenerates Nyam.xcodeproj
├── start.py               # curl helper for testing the Worker
├── Nyam/                  # SwiftUI app sources
│   ├── NyamApp.swift
│   ├── Info.plist
│   ├── Nyam.entitlements
│   ├── Models/
│   ├── Services/
│   └── Views/
└── backend/               # Cloudflare Worker
    ├── package.json
    ├── wrangler.toml
    ├── tsconfig.json
    ├── src/
    │   ├── index.ts
    │   ├── auth.ts
    │   ├── openai.ts
    │   ├── schema.ts
    │   └── types.ts
    └── test/
        └── sample-call.sh
```

## License

MIT (see `LICENSE` — TBD).
