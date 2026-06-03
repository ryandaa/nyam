#!/usr/bin/env bash
# Test the local Worker against a sample plate image.
#
# Usage:
#   ./backend/test/sample-call.sh path/to/plate.jpg [plate_diameter_cm]
#
# Posts the image to http://localhost:8787/scan?dev=1 (auth skipped in dev mode)
# and pretty-prints the JSON response.

set -euo pipefail

IMG="${1:-}"
DIAMETER="${2:-26}"
URL="${NYAM_URL:-http://localhost:8787}"

if [[ -z "$IMG" ]]; then
  echo "usage: $0 path/to/plate.jpg [plate_diameter_cm]" >&2
  exit 1
fi

if [[ ! -f "$IMG" ]]; then
  echo "error: file not found: $IMG" >&2
  exit 1
fi

B64=$(base64 < "$IMG" | tr -d '\n')

PAYLOAD=$(cat <<EOF
{ "image_base64": "$B64", "plate_diameter_cm": $DIAMETER }
EOF
)

echo "POST $URL/scan?dev=1  (image=$IMG, plate_diameter_cm=$DIAMETER)"
echo

curl -sS -X POST "$URL/scan?dev=1" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  | python3 -m json.tool
