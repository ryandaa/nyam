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

### Why a real eval matters

The whole pitch of Nyam vs Cal-AI is *accuracy*. So the eval has to actually measure that — not "the demo looked nice." We compare Nyam's per-item gram estimates against ground-truth kitchen-scale measurements, alongside an unanchored GPT-4o baseline (no plate reference, same prompt structure otherwise). The point isn't to claim production accuracy; it's to show the plate-anchor reduces systematic error.

### Methodology

For each test meal:

1. **Weigh each component on a kitchen scale** (g, to nearest 1 g). Record the ground truth.
2. **Plate the meal on a known plate.** Measure the actual plate diameter with a tape measure (most US dinner plates are 26 cm / 10.2 in, but verify yours).
3. **Photograph overhead** at ~50 cm height, plate centered, plate fully in frame, even lighting. Use the same iPhone for every meal in the eval to remove camera variance.
4. **Run through Nyam** via `python start.py meal_<n>.jpg <diameter_cm>`. Record per-item estimates.
5. **Run the unanchored baseline.** Same photo, prompt OpenAI directly (no plate diameter, no scale anchor):
   ```python
   # baseline: same image, same JSON schema, but the system prompt
   # never mentions the plate or scale anchor.
   ```
6. **Compute Δ%** = `(nyam_g - true_g) / true_g * 100` per item, then again for the baseline. Mean absolute Δ% across all items is the headline number.

### Sample size

Aim for **≥ 5 meals × ~3 components each = 15 measured items**. More is better, but 15 is enough to show whether the plate anchor helps. Mix easy meals (well-separated items, e.g. chicken + rice + broccoli) and hard meals (layered, e.g. stir-fry on rice, salad with dressing).

### Result template

Populate this from your runs:

| Meal | Component | True g | Nyam g | Nyam Δ% | Baseline g | Baseline Δ% |
|---|---|---|---|---|---|---|
| 1 — chicken plate | grilled chicken | | | | | |
| 1 — chicken plate | jasmine rice | | | | | |
| 1 — chicken plate | broccoli | | | | | |
| … | … | | | | | |
| **Mean abs Δ%** | | | | **TBD** | | **TBD** |

### Honest limitations

- One photographer, one phone, one plate type — results don't generalize.
- We're measuring grams, not full nutrition accuracy. Macro values depend on the model's food-knowledge lookup (USDA-style values), which we can't directly verify.
- Layered foods (stir-fry, casseroles) will be wrong for both Nyam and the baseline. The plate anchor only helps when items are visually distinguishable.

## Demo video script (target 3–4 min)

Aligns to the rubric's four prompts: *why*, *how*, *use cases*, *what's next*.

**0:00 – 0:30 · Why this exists**
- Show a Cal-AI screenshot and a kitchen scale next to a real meal.
- "Cal-AI says this rice is 80 g. The scale says 220 g. The model has no scale reference, so it guesses."
- One sentence on the insight: *your plate is a known-size object — make the model use it.*

**0:30 – 1:00 · How it works**
- Architecture diagram (1 slide): iPhone → Vision-framework plate detection → Cloudflare Worker → GPT-4o structured output → results.
- Stress the two things that are new vs Cal-AI: on-device plate detection, and the prompt that anchors gram estimates to the plate's known area.

**1:00 – 2:30 · Live demo on iPhone**
- Open the app, Sign in with Apple (10 sec).
- Camera viewfinder, plate guide overlay.
- Capture the same meal you weighed.
- Calibration sheet: plate diameter prefilled, confirm.
- Results page: per-item grams + macros + totals.
- Tap "Scan again" — show how fast it is.

**2:30 – 3:15 · Accuracy eval**
- One slide with the result table.
- "Across 15 measured items, Nyam's mean error was X%; the unanchored baseline was Y%."
- Be honest about where it failed (layered dishes, etc.).

**3:15 – 4:00 · What's next**
- LiDAR side-view height (iPhone Pro) — the second view the project proposal mentions.
- Food log + daily targets (the standard tracker UX, kept out of V1).
- Restaurant-mode (no plate visible) — needs a different anchor.
- Closing line on impact: cheaper accuracy → trackers that more people can actually rely on.

### Recording tips

- Capture screen with QuickTime → File → New Movie Recording → choose iPhone as source.
- Two phones works too: one to record, one running the app.
- Bad audio sinks the rubric's *Communication* points faster than anything else. Use AirPods or a wired headset, not your laptop mic, and record voiceover separately if needed.

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
