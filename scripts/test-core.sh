#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

# Note: Official Docker Hub `swift:6.0-slim` ships runtime shared libraries only (no `swift` compiler);
# `swift:6.0` is the official Swift 6.0 toolchain image required to run `swift test`.
REQUESTED_IMAGE="${LUNA_SWIFT_DOCKER_IMAGE:-swift:6.0}"
if docker image inspect "$REQUESTED_IMAGE" >/dev/null 2>&1; then
  if ! docker run --rm "$REQUESTED_IMAGE" sh -c 'command -v swift >/dev/null 2>&1'; then
    echo "  [WARN] ${REQUESTED_IMAGE} is a runtime-only image without 'swift'; falling back to swift:6.0 toolchain." >&2
    REQUESTED_IMAGE="swift:6.0"
  fi
fi

SWIFTLINT_IMAGE="${LUNA_SWIFTLINT_DOCKER_IMAGE:-ghcr.io/realm/swiftlint:latest}"
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

if [[ -f "${REPO_ROOT}/.swiftlint.yml" ]]; then
  echo "==> [LunaCore] .swiftlint.yml detected — running SwiftLint (${SWIFTLINT_IMAGE})..."
  docker run --rm \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp \
    -v "${REPO_ROOT}:/workspace:ro" \
    -w /workspace \
    "${SWIFTLINT_IMAGE}" \
    lint --strict
else
  echo "==> [LunaCore] No .swiftlint.yml present; skipping SwiftLint container."
fi

echo "==> [LunaCore] All Linux Swift tests passed."
