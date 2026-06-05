# Nyam: Macro Tracking through Pictures
## CS 153 Final Project
> Take an overhead photo of your plate. Nyam uses the plate as a known-size reference to actually *measure* food portions.


---

## The problem

The current category leader is [Cal AI](https://www.calai.app/), a calorie-tracking app built by two teenagers that crossed millions of downloads in 2024-2025 and was [acquired by MyFitnessPal in March 2026](https://techcrunch.com/2026/03/02/myfitnesspal-has-acquired-cal-ai-the-viral-calorie-app-built-by-teens/). Their stack, [per a March 2025 TechCrunch interview](https://techcrunch.com/2025/03/16/photo-calorie-app-cal-ai-downloaded-over-a-million-times-was-built-by-two-teenagers/) with founder Zach Yadegari, is **frontier vision LLMs from OpenAI and Anthropic plus retrieval over "open source food calorie and image databases from sites like GitHub."** No specific model is named, and no nutrition database is cited. 

Crucially, **Cal AI has no scale anchor in the photo (or any way to measure the size of food in the pictures themselves.** No reference object, no depth sensing, no LiDAR, which was [mentioned] (https://www.cnbc.com/2025/09/06/cal-ai-how-a-teenage-ceo-built-a-fast-growing-calorie-tracking-app.html) by the founder in September 2025:

> "Some of our users expect it to have X-ray vision, where if you take a picture of a bowl of food and you hid things at the bottom of the bowl, it's going to pick it up. It won't."

In other words: a single 2D photo through a vision LLM, with no spatial measurement layer. Their public accuracy figure is a founder-attributed ~90%, which TechCrunch explicitly noted it "couldn't validate." Independent reviewers have reported significant undercounting on mixed and high-fat meals.

I wanted to build Nyam to be a free, open source repo for users who don't want to pay for CalAI, while have competitive performance to the real thing, alongside a few other perks like an on-demand dietician

## How Nyam differs from Cal AI

Same class of model (frontier vision LLM), three additional grounding layers on top:

| Layer | Cal AI | Nyam |
|---|---|---|
| **Vision model** | OpenAI + Anthropic frontier LLMs (per TechCrunch, Mar 2025) | OpenAI GPT-4o |
| **Scale recovery** | None. No reference, no depth, no LiDAR ([CNBC, Sept 2025](https://www.cnbc.com/2025/09/06/cal-ai-how-a-teenage-ceo-built-a-fast-growing-calorie-tracking-app.html)) | ARKit horizontal-plane detection + camera-intrinsic raycasting. Plate diameter is derived from camera physics |
| **Volume measurement** | None. Single 2D photo only (founder, CNBC: "we don't have X-ray vision") | **LiDAR depth scan** on iPhone Pro. Per-pixel depth map integrated to a real food volume in cm³ above the plate plane |
| **Output format** | Not publicly disclosed | Strict JSON schema; model can't return free-text or skip fields |
| **Forced dimensions** | None | Per-item `width_cm × depth_cm × height_cm` are required schema fields, computed *before* grams. On LiDAR, the measured total volume is given to the model as a hard constraint |
| **Nutrition reference** | "Open-source food calorie and image databases from GitHub" (per TechCrunch, Mar 2025) | **USDA FoodData Central API.** Per-item lookup, scaled by the model's grams. Falls back to density / sodium / fiber prompt anchors when USDA has no match. Each item shows USDA vs AI-estimate provenance in the UI |
| **Reasoning chain** | Not disclosed | Explicit 9-step CoT in the system prompt: identify, area %, cm², dimensions, height, volume, grams, macros, sanity check |
| **Graceful degradation** | n/a, one path | Three tiers. **LiDAR** (Pro) for real volume; **AR** (non-Pro) for plate-anchored; **Manual** (library photo / no AR) for user-confirmed plate size. Active tier surfaced in the UI |
| **Accuracy claim** | "~90%" (founder), [unvalidated by TechCrunch](https://techcrunch.com/2025/03/16/photo-calorie-app-cal-ai-downloaded-over-a-million-times-was-built-by-two-teenagers/) | See [Evaluation](#evaluation) section. Reproducible eval set in `eval/images/` |

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

## Setup

### Prerequisites

- macOS with **Xcode 15+** (iOS 17 SDK)
- **Node 20+** and **npm**
- **Cloudflare account** (free tier is plenty) and `wrangler` CLI (`npm i -g wrangler`)
- **OpenAI API key** with `gpt-4o` access (or any other LLM key)
- **USDA FoodData Central API key** (free, instant). Sign up at [api.data.gov/signup](https://api.data.gov/signup/). Optional. Nyam works without it; you just lose per-item USDA grounding
- **Apple Developer account** (free tier works for personal-device testing). Paid tier only required if you swap the V1 stub auth back to real Sign in with Apple
- An **iPhone** for testing (Pro recommended; LiDAR is a planned future feature)

### 1. Backend: Cloudflare Worker

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
npx wrangler secret put USDA_API_KEY     # paste your USDA key (optional but recommended)
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
3. Edit `Nyam/Services/NyamAPI.swift` and set `baseURL` to either your local Worker (use your Mac's LAN IP, e.g. `http://192.168.1.42:8787`) or your deployed Worker URL.
4. Build & Run (⌘R).

## How it works end-to-end

At a high level, the flow goes from the iPhone camera to a results view in about fifteen seconds. When you open the camera, the app is actually running ARKit instead of a regular camera, so it can detect the table as a flat surface and figure out the plate's real-world diameter from camera physics alone, no user input needed. On iPhone Pro it also reads the LiDAR depth map to get the actual cubic centimeters of food on the plate. Once you capture, the image and those measurements get sent to a Cloudflare Worker, which calls GPT-4o with a strict JSON schema that forces the model to commit to per-item dimensions before estimating macros. The Worker then takes every food name the model identified and looks it up in USDA's FoodData Central database, replacing the model's macro guesses with US government data. What you see on the results screen is either USDA-grounded or marked with an AI-estimate badge so the provenance is honest, and the whole entry gets saved locally so it shows up in the Home feed.

### Honest limitations
- We're measuring grams, not full nutrition accuracy. Macro values depend on the model's food-knowledge lookup (USDA-style values), which we can't directly verify.
- Layered foods (stir-fry, casseroles) will be wrong for both Nyam and the baseline. The plate anchor only helps when items are visually distinguishable. We try and counteract this with the LIDAR system

## AI usage disclosure

I used Claude Code with Opus 4.7 to help scaffold the project structure and to also help build the frontend UI. Architecture, app features, and frontend UI decisions were thought of by me. The prompts were also built by me. Although, most of the code was built by the LLM. No code aws forked in the process.

I also used GPT-4o for LLM calls

## Future work
There are a few things I want to keep working on. The biggest one is expanding the core food database so every food lookup hits a USDA-approved value instead of falling back on the model's estimates. Partially hidden foods are also still tough, since right now the app only sees one overhead photo, so layered dishes and bowls of soup with toppings throw it off. Weight goals are planned but not in the build yet. The LiDAR depth-based volume only works on iPhone Pro models, so the next step is a side-view companion capture to estimate food height, which was actually the second view I mentioned in my original project proposal. And on plate detection, Vision's rectangle detection works well on round plates against contrasting tablecloths, but rectangular plates and busy backgrounds still degrade the accuracy.

## Repo layout

```
nyam/
├── README.md
├── project.yml            # xcodegen config, regenerates Nyam.xcodeproj
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
