#!/usr/bin/env bash
# Stops or starts the DocumentDB cluster and waits for the end state (the AWS provider has no Terraform resource
# for the running state of a DocumentDB cluster, unlike aws_rds_instance_state for RDS).
# Usage: scripts/docdb-estado.sh detener|arrancar <cluster id>
#   detener:  available → stopped (Pausar). Already stopped: nothing to do.
#   arrancar: stopped → available (Provision, before the base stack). Missing cluster (first deploy) or already
#             available: nothing to do.
# Needs AWS credentials. ESPERA_S / INTENTOS tune the polling (default 20 s × 90 = 30 min).
set -euo pipefail

if [[ $# -ne 2 || ( "$1" != detener && "$1" != arrancar ) ]]; then
  echo "usage: $0 detener|arrancar <cluster id>" >&2
  exit 2
fi
accion="$1"
cluster="$2"

estado() {
  aws docdb describe-db-clusters --db-cluster-identifier "$cluster" --query 'DBClusters[0].Status' --output text
}

err="$(mktemp)"
trap 'rm -f "$err"' EXIT
if ! actual="$(estado 2>"$err")"; then
  if grep -q DBClusterNotFoundFault "$err"; then
    if [[ "$accion" == arrancar ]]; then
      echo "Cluster $cluster does not exist yet: nothing to start."
      exit 0
    fi
    echo "::error::Cluster $cluster does not exist: nothing to stop." >&2
    exit 1
  fi
  cat "$err" >&2
  exit 1
fi

if [[ "$accion" == detener ]]; then
  objetivo=stopped
  if [[ "$actual" == available ]]; then
    aws docdb stop-db-cluster --db-cluster-identifier "$cluster" >/dev/null
    echo "Stopping $cluster…"
  fi
else
  objetivo=available
  if [[ "$actual" == stopped ]]; then
    aws docdb start-db-cluster --db-cluster-identifier "$cluster" >/dev/null
    echo "Starting $cluster…"
  fi
fi

for _ in $(seq 1 "${INTENTOS:-90}"); do
  actual="$(estado)"
  if [[ "$actual" == "$objetivo" ]]; then
    echo "Cluster $cluster is $objetivo."
    exit 0
  fi
  sleep "${ESPERA_S:-20}"
done
echo "::error::Cluster $cluster is still $actual, expected $objetivo." >&2
exit 1
