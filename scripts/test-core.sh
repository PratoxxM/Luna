#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

# Note: Official Docker Hub `swift:6.2-slim` ships runtime shared libraries only (no `swift` compiler);
# `swift:6.2` is the official Swift 6.2 toolchain image required to run `swift test`.
REQUESTED_IMAGE="${LUNA_SWIFT_DOCKER_IMAGE:-swift:6.2}"
if docker image inspect "$REQUESTED_IMAGE" >/dev/null 2>&1; then
  if ! docker run --rm "$REQUESTED_IMAGE" sh -c 'command -v swift >/dev/null 2>&1'; then
    echo "  [WARN] ${REQUESTED_IMAGE} is a runtime-only image without 'swift'; falling back to swift:6.2 toolchain." >&2
    REQUESTED_IMAGE="swift:6.2"
  fi
fi

SCRATCH_DIR=".build-linux"

echo "==> [LunaCore] Running Linux x86_64 Swift tests in ${REQUESTED_IMAGE}..."
mkdir -p "${REPO_ROOT}/${SCRATCH_DIR}"

docker run --rm \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -v "${REPO_ROOT}:/workspace" \
  -w /workspace \
  "${REQUESTED_IMAGE}" \
  swift test --scratch-path "${SCRATCH_DIR}" --parallel

echo "==> [LunaCore] All Linux Swift tests passed."
