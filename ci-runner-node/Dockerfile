# ci-runner-node: a GitHub Actions runner image for Node projects.
#
# Upstream's ghcr.io/actions/actions-runner is a bare runner: Ubuntu 24.04, git, curl, jq,
# the runner binary, nothing a Node project needs. A job on it installs Node and a browser at
# job time and has none of the libraries a headless browser needs. This bakes all of that in,
# so a job downloads nothing it could know ahead:
#   - Node in RUNNER_TOOL_CACHE (actions/setup-node finds it: `<ver>/x64` + `x64.complete`),
#     and on PATH; pnpm global.
#   - Chromium's apt library set via Playwright's own `install-deps` for the pinned release,
#     and that release's Chromium build in /home/runner/.cache/ms-playwright (a workflow's
#     cache step then restores nothing and `playwright install` is a no-op).
#
# Build with build.sh, never `docker build` directly: it supplies the pins from versions.env
# and proves the result offline (versions, tool-cache marker, every Chromium library
# resolves, headless Chromium renders a page as the runner user).
#
# RUNNER_TOOL_CACHE: actions-runner-controller mounts an emptyDir over /home/runner/_work,
# where the runner would otherwise put its tool cache, so the baked cache lives outside it
# and the env names it.
ARG RUNNER_VERSION
FROM ghcr.io/actions/actions-runner:${RUNNER_VERSION}

ARG NODE_VERSION
ARG NODE_SHA256
ARG PNPM_VERSION
ARG PLAYWRIGHT_VERSION

USER root
ENV DEBIAN_FRONTEND=noninteractive
ENV RUNNER_TOOL_CACHE=/opt/hostedtoolcache

RUN set -eu; \
    : "${NODE_VERSION:?}" "${NODE_SHA256:?}" "${PNPM_VERSION:?}" "${PLAYWRIGHT_VERSION:?}"; \
    d="$RUNNER_TOOL_CACHE/node/$NODE_VERSION/x64"; mkdir -p "$d"; \
    curl -fsSL --retry 3 -o /tmp/node.tar.gz "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64.tar.gz"; \
    echo "$NODE_SHA256  /tmp/node.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/node.tar.gz -C "$d" --strip-components=1; rm -f /tmp/node.tar.gz; \
    touch "$RUNNER_TOOL_CACHE/node/$NODE_VERSION/x64.complete"; \
    for b in node npm npx corepack; do ln -s "$d/bin/$b" "/usr/local/bin/$b"; done; \
    npm install -g "pnpm@$PNPM_VERSION" && ln -s "$d/bin/pnpm" /usr/local/bin/pnpm; \
    npm cache clean --force; \
    chown -R runner:docker "$RUNNER_TOOL_CACHE"

# Chromium's shared libraries, as Playwright itself resolves them for this release (the
# same list `--with-deps` would apt-install on every job, where a slow mirror stalls the
# job). Fonts included: a smoke test that renders real text needs them.
RUN set -eu; \
    npx --yes "playwright@$PLAYWRIGHT_VERSION" install-deps chromium; \
    rm -rf /var/lib/apt/lists/* /root/.npm /root/.cache

USER runner
# The browser builds themselves, owned by the runner user, where @playwright/test looks.
RUN set -eu; \
    npx --yes "playwright@$PLAYWRIGHT_VERSION" install chromium; \
    rm -rf /home/runner/.npm
