#!/usr/bin/env python3
"""
nyam test harness — post a plate image to the deployed Cloudflare Worker and
pretty-print the structured nutrition result.

Usage:
    python start.py path/to/plate.jpg
    python start.py path/to/plate.jpg 28          # plate is 28 cm
    NYAM_URL=https://nyam-backend.ryandaa.workers.dev python start.py meal.jpg

Defaults:
    plate_diameter_cm = 26 (standard 10in dinner plate)
    NYAM_URL          = https://nyam-backend.ryandaa.workers.dev
    auth              = ?dev=1 (skips Apple JWT verification)

This script is the same flow the iOS app uses — base64 the image, POST it to
/scan with the plate diameter, decode ScanResult. It exists so you can eyeball
the model's behavior before Xcode finishes installing, and so we can run the
accuracy eval (kitchen-scaled meals) without firing up the phone.
"""

from __future__ import annotations

import base64
import json
import os
import sys
import urllib.error
import urllib.request
from typing import Any

DEFAULT_URL = os.environ.get("NYAM_URL", "https://nyam-backend.ryandaa.workers.dev")
DEFAULT_DIAMETER_CM = 26.0
TIMEOUT_SEC = 90


def post_scan(image_path: str, diameter_cm: float, base_url: str) -> dict[str, Any]:
    with open(image_path, "rb") as f:
        image_b64 = base64.b64encode(f.read()).decode("ascii")

    payload = {"image_base64": image_b64, "plate_diameter_cm": diameter_cm}
    url = f"{base_url.rstrip('/')}/scan?dev=1"

    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT_SEC) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        raise SystemExit(f"HTTP {e.code} from Worker:\n{body}")
    except urllib.error.URLError as e:
        raise SystemExit(f"Network error: {e.reason}")


def print_table(result: dict[str, Any]) -> None:
    items = result.get("items") or []
    if not result.get("plate_detected"):
        print("⚠️  Worker says no plate detected in the image.\n")
    if not items:
        print("No food items returned.")
        return

    name_w = max(len("FOOD"), max(len(item["name"]) for item in items))
    print(f"\n{'FOOD':{name_w}}  {'GRAMS':>6}  {'KCAL':>6}  {'P':>5}  {'C':>5}  {'F':>5}  {'PLATE%':>7}")
    print("-" * (name_w + 50))
    for item in items:
        print(
            f"{item['name']:{name_w}}  "
            f"{int(round(item['estimated_grams'])):>6}  "
            f"{int(round(item['calories'])):>6}  "
            f"{item['protein_g']:>5.1f}  "
            f"{item['carbs_g']:>5.1f}  "
            f"{item['fat_g']:>5.1f}  "
            f"{item['plate_area_percent']:>6.0f}%"
        )

    totals = result["totals"]
    print("-" * (name_w + 50))
    print(
        f"{'TOTAL':{name_w}}  "
        f"{'':>6}  "
        f"{int(round(totals['calories'])):>6}  "
        f"{totals['protein_g']:>5.1f}  "
        f"{totals['carbs_g']:>5.1f}  "
        f"{totals['fat_g']:>5.1f}"
    )


def main() -> None:
    if len(sys.argv) < 2 or sys.argv[1] in {"-h", "--help"}:
        print(__doc__)
        sys.exit(0 if "-h" in sys.argv or "--help" in sys.argv else 1)

    image_path = sys.argv[1]
    if not os.path.isfile(image_path):
        raise SystemExit(f"file not found: {image_path}")

    diameter = float(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_DIAMETER_CM

    print(f"POST {DEFAULT_URL}/scan?dev=1")
    print(f"  image:              {image_path}")
    print(f"  plate_diameter_cm:  {diameter}")
    print("  (auth bypassed via ?dev=1 — fine for local testing)")
    print()

    result = post_scan(image_path, diameter, DEFAULT_URL)

    print_table(result)
    print("\n--- raw JSON ---")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
