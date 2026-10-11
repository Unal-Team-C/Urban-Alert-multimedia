#!/usr/bin/env bash
# Runs the one-off init function (DocumentDB indexes) inside the private network and fails when it fails
# (spec 002 RF-007, plan D-007). Run after the stack servicio and before the stack rutas.
# Usage: scripts/run-init.sh <function-name>      (needs AWS credentials and jq; the AWS CLI reads AWS_REGION)
set -euo pipefail

FUNCTION=${1:?usage: run-init.sh <function-name>}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Terraform already waits for both states; this keeps the script safe to run on its own.
aws lambda wait function-active-v2 --function-name "$FUNCTION"
aws lambda wait function-updated-v2 --function-name "$FUNCTION"

aws lambda invoke --function-name "$FUNCTION" --log-type Tail \
  --cli-binary-format raw-in-base64-out --payload '{}' "$TMP/response.json" > "$TMP/meta.json"

echo "--- Last log lines of $FUNCTION ---"
jq -r '.LogResult // empty' "$TMP/meta.json" | base64 -d || true
echo "--- Response ---"
cat "$TMP/response.json"
echo

if [ -n "$(jq -r '.FunctionError // empty' "$TMP/meta.json")" ]; then
  echo "::error::The init function $FUNCTION failed (network, DocumentDB secret or TLS): see the log above."
  exit 1
fi
echo "Init done: indexes ready."
