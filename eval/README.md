# eval/

Canonical evaluation set for the README accuracy table. Photos here are
**committed** so anyone can reproduce the eval.

## Layout

```
eval/
├── images/                   # overhead photos of weighed meals (kept small, ~500 KB each)
│   ├── meal-1-chicken-rice-broccoli.jpg
│   └── …
└── README.md                 # this file
```

## Per-meal procedure

1. Weigh each component on a kitchen scale (g, nearest 1 g). Record below.
2. Plate the meal on a known-diameter plate. Measure that diameter with a
   tape measure.
3. Photograph **overhead** at ~50 cm height, plate centered, plate fully in
   frame, even lighting. Save under `eval/images/meal-<n>-<short-desc>.jpg`.
4. Run through Nyam:
   ```bash
   python start.py eval/images/meal-1-chicken-rice-broccoli.jpg 26
   ```
5. Record per-item grams and the totals row in `eval/results.md` (one row per
   item per meal) and also in the headline table in the project README.

## Why a separate folder

`samples/` is for throwaway testing and is gitignored. `eval/` is the
canonical reproducible set used to make the accuracy claims in the README
and the demo video. Keep it small (a handful of meals, JPEG q ≤ 0.6).
