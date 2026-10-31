#!/bin/sh
# Build the ci-runner-node image from versions.env, then prove it.
# CI (.github/workflows/ci-runner-node.yml) and a local run call this same script.
#
#   ci-runner-node/build.sh <image-ref>
#
# The proof runs the image with no network, as the runner user, and requires: the pinned
# Node on PATH and in the tool cache with its `.complete` marker (what actions/setup-node
# checks before downloading), pnpm at its pin, every shared library of the bundled Chromium
# resolving, and headless Chromium rendering a page. Those are the properties a consuming
# workflow depends on to run without installing anything.
set -eu
cd "$(dirname "$0")/.."
ref="${1:?usage: build.sh <image-ref>}"
pins=ci-runner-node/versions.env

pin() {
  v=$(sed -n "s/^$1=\([^ #]*\).*/\1/p" "$pins")
  [ -n "$v" ] || { echo "build.sh: $1 is not set in $pins" >&2; exit 1; }
  printf '%s' "$v"
}
RUNNER_VERSION=$(pin RUNNER_VERSION); NODE_VERSION=$(pin NODE_VERSION); NODE_SHA256=$(pin NODE_SHA256)
PNPM_VERSION=$(pin PNPM_VERSION); PLAYWRIGHT_VERSION=$(pin PLAYWRIGHT_VERSION)
export RUNNER_VERSION NODE_VERSION NODE_SHA256 PNPM_VERSION PLAYWRIGHT_VERSION

echo "build.sh: runner $RUNNER_VERSION, node $NODE_VERSION, pnpm $PNPM_VERSION, playwright $PLAYWRIGHT_VERSION -> $ref"
# The source label links the GHCR package to this repository, so it inherits the repo's
# access permissions and shows its README. Visibility is NOT inherited: a new package
# starts private and is made public once, by hand, in the package settings.
docker build --platform linux/amd64 \
  --build-arg RUNNER_VERSION --build-arg NODE_VERSION --build-arg NODE_SHA256 \
  --build-arg PNPM_VERSION --build-arg PLAYWRIGHT_VERSION \
  --label org.opencontainers.image.source=https://github.com/whi-hq/runner-images \
  --label org.opencontainers.image.revision="$(git rev-parse HEAD)" \
  --label org.opencontainers.image.licenses=MIT \
  --label org.opencontainers.image.description="GitHub Actions runner: Node $NODE_VERSION, pnpm, Chromium" \
  -t "$ref" ci-runner-node

echo "build.sh: offline proof"
docker run --rm --network none --platform linux/amd64 --user runner --entrypoint /bin/sh \
  -e NODE_VERSION -e PNPM_VERSION "$ref" -c '
    set -eu; fail() { echo "build.sh: $*"; exit 1; }
    [ "$(node --version)" = "v$NODE_VERSION" ] || fail "node is $(node --version), pinned v$NODE_VERSION"
    [ "$(pnpm --version)" = "$PNPM_VERSION" ] || fail "pnpm is $(pnpm --version), pinned $PNPM_VERSION"
    [ -f "$RUNNER_TOOL_CACHE/node/$NODE_VERSION/x64.complete" ] || fail "tool-cache marker missing: setup-node would download"
    [ -w "$RUNNER_TOOL_CACHE" ] || fail "tool cache not writable by runner"
    chrome=$(find /home/runner/.cache/ms-playwright -type f -name chrome -path "*chromium-*" | head -1)
    [ -n "$chrome" ] || fail "no Chromium under ~/.cache/ms-playwright"
    missing=$(ldd "$chrome" | grep -c "not found" || true)
    [ "$missing" = 0 ] || { ldd "$chrome" | grep "not found"; fail "$missing Chromium libraries unresolved"; }
    "$chrome" --headless=new --no-sandbox --disable-gpu --dump-dom "data:text/html,<title>ci-runner-node</title>" 2>/dev/null | grep -q "ci-runner-node" \
      || fail "headless Chromium did not render"
    echo "build.sh: node v$NODE_VERSION in tool cache, pnpm $PNPM_VERSION, Chromium libraries resolve, headless render ok"'
