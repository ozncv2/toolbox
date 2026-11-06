#!/usr/bin/env bash
# Scans an image from the local Docker daemon with Trivy and Grype, then applies scripts/cve_gate.py.
# Usage: scripts/scan.sh <image> [report-dir]
#
# The scanners read an exported tar, so they never get the Docker socket or registry credentials.
set -euo pipefail

TRIVY_IMAGE=aquasec/trivy:0.76.2@sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb
GRYPE_IMAGE=anchore/grype:v0.121.2@sha256:6a36234da13f9faa327306ac0b3dab3405cfa2b4eb20c8f904125a8707863913

image=$1
reports=$(mkdir -p "${2:-reports}" && cd "${2:-reports}" && pwd)
root=$(cd "$(dirname "$0")/.." && pwd)

docker save "$image" -o "$reports/image.tar"
trap 'rm -f "$reports/image.tar"' EXIT

docker run --rm \
    --volume "$reports:/work" \
    --volume toolbox-trivy-cache:/root/.cache/trivy \
    "$TRIVY_IMAGE" image --quiet --timeout 30m --scanners vuln \
    --format json --output /work/trivy.json --input /work/image.tar

docker run --rm \
    --volume "$reports:/work" \
    --volume toolbox-grype-cache:/grype-db \
    --env GRYPE_DB_CACHE_DIR=/grype-db \
    "$GRYPE_IMAGE" docker-archive:/work/image.tar --quiet --output json --file /work/grype.json

python3 "$root/scripts/cve_gate.py" "$reports/trivy.json" "$reports/grype.json"
