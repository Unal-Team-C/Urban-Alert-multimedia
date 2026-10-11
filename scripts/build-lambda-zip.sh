#!/usr/bin/env bash
# Builds the Lambda package (runtime python3.13, x86_64) as a deterministic .zip: the same sources give the same
# bytes, so Terraform's source_code_hash only changes when the code, a dependency or the CA bundle change
# (spec 002 RF-001, RNF-003; plan D-010).
# Usage: scripts/build-lambda-zip.sh [output.zip]      (default: build/multimedia.zip; needs python3, zip, curl)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/build/multimedia.zip}"
PKG="$ROOT/build/pkg"
# Lambda limit for a direct upload (Terraform `filename`); above it the package would have to go through S3.
MAX_BYTES=52428800
CA_URL="https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem"

rm -rf "$PKG" "$OUT"
mkdir -p "$PKG/certs" "$(dirname "$OUT")"

# Binary wheels built for Lambda (manylinux, CPython 3.13, x86_64), whatever the machine running the build.
# --no-compile: .pyc files embed timestamps and would change the hash on every build.
python3 -m pip install --quiet --disable-pip-version-check --no-compile \
  --platform manylinux2014_x86_64 --implementation cp --python-version 3.13 --only-binary=:all: \
  --target "$PKG" -r "$ROOT/requirements.txt"

cp -R "$ROOT/app" "$PKG/app"
# TLS to DocumentDB: the URI points tlsCAFile to /var/task/certs/global-bundle.pem (plan §7.2).
curl --fail --silent --show-error --location --output "$PKG/certs/global-bundle.pem" "$CA_URL"

find "$PKG" -name "__pycache__" -type d -prune -exec rm -rf {} +
find "$PKG" -name "*.pyc" -delete
# Fixed permissions and dates, sorted entries, no extra attributes (-X) or directory entries (-D).
chmod -R u=rwX,go=rX "$PKG"
find "$PKG" -exec touch -h -t 198001010000 {} +
(cd "$PKG" && find . -type f | LC_ALL=C sort | sed 's|^\./||' | zip -q -X -D -@ "$OUT")

size=$(wc -c < "$OUT" | tr -d ' ')
if command -v sha256sum >/dev/null 2>&1; then
  sha=$(sha256sum "$OUT" | cut -d' ' -f1)
else
  sha=$(shasum -a 256 "$OUT" | cut -d' ' -f1)
fi
echo "Package: $OUT ($size bytes, sha256 $sha)"
if [ "$size" -gt "$MAX_BYTES" ]; then
  echo "::error::The Lambda package is $size bytes, above the $MAX_BYTES bytes of a direct upload."
  exit 1
fi
