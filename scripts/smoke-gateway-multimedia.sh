#!/usr/bin/env bash
# Smoke test after provisioning (spec 002 RF-010, plan §4.3 step 8). Writes nothing: the bucket is persistent.
#   1. GET metadata of a random id through the gateway → the service's own 404 (gateway → Lambda → Secrets Manager
#      → DocumentDB works; the gateway's 404 for unknown routes has another body).
#   2. GET /api/v1/multimedia/docs → 404 (only the two routes are published).
#   3. GET <image-base-url>/ → 403 (anonymous listing denied) and an unknown key → 403 (plan D-015).
# Usage: scripts/smoke-gateway-multimedia.sh <gateway-url> <image-base-url>
set -euo pipefail

GATEWAY=${1:?usage: smoke-gateway-multimedia.sh <gateway-url> <image-base-url>}
IMAGES=${2:?missing image-base-url}
PREFIX="$GATEWAY/api/v1/multimedia"
BODY=$(mktemp)
trap 'rm -f "$BODY"' EXIT
failures=0

status() { curl --silent --show-error --output "$BODY" --write-out '%{http_code}' --max-time 20 "$1"; }

expect() {
  local name=$1 expected=$2 url=$3 got
  got=$(status "$url")
  if [ "$got" = "$expected" ]; then
    echo "ok   $name: $got"
  else
    echo "::error::$name: expected $expected, got $got ($url): $(head -c 300 "$BODY")"
    failures=$((failures + 1))
  fi
}

id=$(python3 -c 'import uuid; print(uuid.uuid4())')

# New routes and a cold function in the VPC can take a few seconds: retry the first check only.
for attempt in 1 2 3 4 5 6; do
  got=$(status "$PREFIX/images/$id/metadata")
  if [ "$got" = "404" ] && grep -q '"Image not found"' "$BODY"; then
    break
  fi
  echo "attempt $attempt: metadata answered $got: $(head -c 200 "$BODY")"
  sleep 10
done
if [ "$got" = "404" ] && grep -q '"Image not found"' "$BODY"; then
  echo "ok   metadata of an unknown image through the gateway: 404 Image not found"
else
  echo "::error::metadata of an unknown image: expected the service's 404 \"Image not found\", got $got: $(head -c 300 "$BODY")"
  failures=$((failures + 1))
fi

expect "unpublished route /docs" 404 "$PREFIX/docs"
expect "anonymous listing of the images bucket" 403 "$IMAGES/"
expect "unknown image key" 403 "$IMAGES/$id.jpg"

if [ "$failures" -gt 0 ]; then
  echo "Smoke test failed: $failures check(s)."
  exit 1
fi
echo "Smoke test passed."
