#!/usr/bin/env bash
# Invoke the local Lambda (RIE) with an API Gateway HTTP API v2 event, as the cloud would.
# Usage: scripts/invoke-upload.sh <image.jpg|image.png> [capturedAt] [lat] [lon]
#   e.g. scripts/invoke-upload.sh photo.jpg 2026-10-06T16:12:05-05:00 4.6097 -74.0817
set -euo pipefail

IMAGE=${1:?usage: invoke-upload.sh <image.jpg|image.png> [capturedAt] [lat] [lon]}
if [ ! -f "$IMAGE" ]; then
  echo "invoke-upload.sh: file not found: $IMAGE" >&2
  exit 1
fi
URL=${MULTIMEDIA_INVOKE_URL:-http://localhost:9010/2015-03-31/functions/function/invocations}
BOUNDARY="----urbanalert$$"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

CONTENT_TYPE=image/jpeg
case "$IMAGE" in *.png | *.PNG) CONTENT_TYPE=image/png ;; esac

field() { printf -- '--%s\r\nContent-Disposition: form-data; name="%s"\r\n\r\n%s\r\n' "$BOUNDARY" "$1" "$2"; }
{
  if [ -n "${2:-}" ]; then field capturedAt "$2"; fi
  if [ -n "${3:-}" ]; then field lat "$3"; field lon "${4:?lon is required with lat}"; fi
  printf -- '--%s\r\nContent-Disposition: form-data; name="image"; filename="%s"\r\nContent-Type: %s\r\n\r\n' \
    "$BOUNDARY" "$(basename "$IMAGE")" "$CONTENT_TYPE"
  cat "$IMAGE"
  printf '\r\n--%s--\r\n' "$BOUNDARY"
} > "$TMP/body"

LENGTH=$(wc -c < "$TMP/body" | tr -d ' ')
BODY=$(base64 < "$TMP/body" | tr -d '\n')
cat > "$TMP/event.json" <<JSON
{"version":"2.0","routeKey":"\$default","rawPath":"/api/v1/multimedia/images","rawQueryString":"",
 "headers":{"content-type":"multipart/form-data; boundary=$BOUNDARY","content-length":"$LENGTH"},
 "requestContext":{"accountId":"000000000000","apiId":"local","domainName":"localhost","domainPrefix":"localhost",
  "http":{"method":"POST","path":"/api/v1/multimedia/images","protocol":"HTTP/1.1","sourceIp":"127.0.0.1","userAgent":"invoke-upload.sh"},
  "requestId":"local","routeKey":"\$default","stage":"\$default","time":"","timeEpoch":0},
 "body":"$BODY","isBase64Encoded":true}
JSON

curl -s -X POST "$URL" --data-binary @"$TMP/event.json"
echo
