#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUT_DIR="${1:-${REPO_ROOT}/.ci-screenshots/local-preview}"
PLAYWRIGHT_IMAGE="${LUNA_PLAYWRIGHT_DOCKER_IMAGE:-mcr.microsoft.com/playwright/python:v1.47.0-jammy}"

mkdir -p "$OUT_DIR"
OUT_ABS="$(cd "$OUT_DIR" && pwd)"

echo "==> [Luna Preview] Rendering 1920x1080 Focus Sandbox via ${PLAYWRIGHT_IMAGE}..."
docker run --rm -i \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp \
  -e PLAYWRIGHT_BROWSERS_PATH=/ms-playwright \
  -v "${REPO_ROOT}/preview:/preview:ro" \
  -v "${OUT_ABS}:/out" \
  "${PLAYWRIGHT_IMAGE}" \
  bash -s <<'SH'
set -euo pipefail

if python3 -c "import playwright" >/dev/null 2>&1; then
  python3 - <<'PY'
from playwright.sync_api import sync_playwright

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    page = browser.new_page(viewport={"width": 1920, "height": 1080}, device_scale_factor=1)

    page.goto("file:///preview/index.html?screen=home&guides=1")
    page.wait_for_timeout(150)
    page.keyboard.press("ArrowRight")
    page.wait_for_timeout(200)
    page.screenshot(path="/out/preview-home.png")

    page.keyboard.press("ArrowDown")
    page.wait_for_timeout(200)
    page.screenshot(path="/out/preview-home-poster-focus.png")

    page.goto("file:///preview/index.html?screen=catalog&guides=1")
    page.wait_for_timeout(150)
    page.keyboard.press("ArrowDown")
    page.wait_for_timeout(200)
    page.screenshot(path="/out/preview-catalog.png")

    page.goto("file:///preview/index.html?screen=details&guides=1")
    page.wait_for_timeout(200)
    page.screenshot(path="/out/preview-details.png")

    page.goto("file:///preview/index.html?screen=player&guides=1")
    page.wait_for_timeout(200)
    page.screenshot(path="/out/preview-player.png")

    browser.close()
print("  [OK] Captured 5 1920x1080 sandbox screenshots via Playwright Python -> /out")
PY
else
  CHROME_BIN="$(find /ms-playwright -name chrome -type f 2>/dev/null | head -n 1)"
  if [[ -z "$CHROME_BIN" ]]; then
    echo "Error: Neither Python playwright nor /ms-playwright chrome binary found in container." >&2
    exit 1
  fi
  render_url() {
    local url="$1"
    local dest="$2"
    "$CHROME_BIN" --headless --no-sandbox --disable-gpu --disable-dev-shm-usage \
      --hide-scrollbars --window-size=1920,1080 --screenshot="$dest" "$url" 2>/dev/null
  }
  render_url "file:///preview/index.html?screen=home&guides=1&focus=right" "/out/preview-home.png"
  render_url "file:///preview/index.html?screen=home&guides=1&focus=down" "/out/preview-home-poster-focus.png"
  render_url "file:///preview/index.html?screen=catalog&guides=1&focus=down" "/out/preview-catalog.png"
  render_url "file:///preview/index.html?screen=details&guides=1" "/out/preview-details.png"
  render_url "file:///preview/index.html?screen=player&guides=1" "/out/preview-player.png"
  echo "  [OK] Captured 5 1920x1080 sandbox screenshots via headless Chromium -> /out"
fi
SH
