#!/usr/bin/env bash
# Fails before anything is changed when the shared platform (Unal-Team-C/urban-alert-plataforma) is not
# provisioned: every parameter of its SSM contract must exist (spec 002 RF-010, plan §4.3).
# Copied from urban-alert-geoespacial/scripts/check-platform.sh.
# Usage: scripts/check-platform.sh            (needs AWS credentials; the AWS CLI reads AWS_REGION)
set -euo pipefail

PREFIX="${PLATFORM_SSM_PREFIX:-/urban-alert/plataforma/}"
REQUIRED=(region vpc-id vpc-cidr subredes-privadas api-id api-endpoint api-execution-arn vpc-link-id vpc-link-sg-id)

names=()
for parameter in "${REQUIRED[@]}"; do
  names+=("${PREFIX}${parameter}")
done

# GetParameters returns the missing names instead of failing, so one call tells exactly what is absent.
missing=$(aws ssm get-parameters --names "${names[@]}" --query 'InvalidParameters' --output text)

if [[ -n "$missing" && "$missing" != "None" ]]; then
  echo "::error::La plataforma compartida no está aprovisionada (urban-alert-plataforma): faltan ${missing//$'\t'/ }"
  echo "Aprovisiona primero la plataforma (workflow Provision de Unal-Team-C/urban-alert-plataforma)."
  exit 1
fi
echo "Plataforma compartida disponible (${#REQUIRED[@]} parámetros en ${PREFIX})."
