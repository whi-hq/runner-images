#!/bin/sh
# Build the ci-runner-infra image from versions.env, then prove it.
# CI (.github/workflows/ci-runner-infra.yml) and a local run call this same script.
#
#   ci-runner-infra/build.sh <image-ref>
#
# The proof runs the image with no network, as the runner user, and requires: every pinned
# tool on PATH at its pin (ansible-core, ansible-lint, yq, gitleaks, pwsh), Python 3.12 with
# the venv first on PATH and writable by the runner (so a workflow's own pip pins can
# upgrade in place), and shellcheck, gpg and pwsh each doing real work rather than only
# printing a version.
set -eu
cd "$(dirname "$0")/.."
ref="${1:?usage: build.sh <image-ref>}"
pins=ci-runner-infra/versions.env

pin() {
  v=$(sed -n "s/^$1=\([^ #]*\).*/\1/p" "$pins")
  [ -n "$v" ] || { echo "build.sh: $1 is not set in $pins" >&2; exit 1; }
  printf '%s' "$v"
}
RUNNER_VERSION=$(pin RUNNER_VERSION)
ANSIBLE_CORE_VERSION=$(pin ANSIBLE_CORE_VERSION); ANSIBLE_LINT_VERSION=$(pin ANSIBLE_LINT_VERSION)
YQ_VERSION=$(pin YQ_VERSION); YQ_SHA256=$(pin YQ_SHA256)
GITLEAKS_VERSION=$(pin GITLEAKS_VERSION); GITLEAKS_SHA256=$(pin GITLEAKS_SHA256)
PWSH_VERSION=$(pin PWSH_VERSION); PWSH_SHA256=$(pin PWSH_SHA256)
export RUNNER_VERSION ANSIBLE_CORE_VERSION ANSIBLE_LINT_VERSION YQ_VERSION YQ_SHA256 \
  GITLEAKS_VERSION GITLEAKS_SHA256 PWSH_VERSION PWSH_SHA256

echo "build.sh: runner $RUNNER_VERSION, ansible-core $ANSIBLE_CORE_VERSION, ansible-lint $ANSIBLE_LINT_VERSION, yq $YQ_VERSION, gitleaks $GITLEAKS_VERSION, pwsh $PWSH_VERSION -> $ref"
# The source label links the GHCR package to this repository (permissions and README).
docker build --platform linux/amd64 \
  --build-arg RUNNER_VERSION --build-arg ANSIBLE_CORE_VERSION --build-arg ANSIBLE_LINT_VERSION \
  --build-arg YQ_VERSION --build-arg YQ_SHA256 --build-arg GITLEAKS_VERSION --build-arg GITLEAKS_SHA256 \
  --build-arg PWSH_VERSION --build-arg PWSH_SHA256 \
  --label org.opencontainers.image.source=https://github.com/whi-hq/runner-images \
  --label org.opencontainers.image.revision="$(git rev-parse HEAD)" \
  --label org.opencontainers.image.licenses=MIT \
  --label org.opencontainers.image.description="GitHub Actions runner: Python 3.12, ansible-core, ansible-lint, yq, shellcheck, gitleaks, PowerShell 7" \
  -t "$ref" ci-runner-infra

echo "build.sh: offline proof"
docker run --rm --network none --platform linux/amd64 --user runner --entrypoint /bin/bash \
  -e ANSIBLE_CORE_VERSION -e ANSIBLE_LINT_VERSION -e YQ_VERSION -e GITLEAKS_VERSION -e PWSH_VERSION "$ref" -c '
    set -eu; fail() { echo "build.sh: $*"; exit 1; }
    [ "$(command -v python3)" = /opt/venv/bin/python3 ] || fail "venv python is not first on PATH: $(command -v python3)"
    python3 -c "import sys; assert sys.version_info[:2] == (3, 12), sys.version" || fail "python is not 3.12"
    [ -w /opt/venv/lib/python3.12/site-packages ] || fail "venv not writable by runner: a workflow pip pin could not upgrade"
    got=$(python3 -c "import ansible.release as r; print(r.__version__)"); [ "$got" = "$ANSIBLE_CORE_VERSION" ] || fail "ansible-core is $got, pinned $ANSIBLE_CORE_VERSION"
    got=$(python3 -c "from importlib.metadata import version; print(version(\"ansible-lint\"))"); [ "$got" = "$ANSIBLE_LINT_VERSION" ] || fail "ansible-lint is $got, pinned $ANSIBLE_LINT_VERSION"
    ansible-playbook --version >/dev/null || fail "ansible-playbook does not run"
    ansible-lint --offline --version >/dev/null 2>&1 || fail "ansible-lint does not run"
    yq --version | grep -q "v$YQ_VERSION\$" || fail "yq is $(yq --version), pinned v$YQ_VERSION"
    [ "$(printf "a: 1\n" | yq -r .a)" = 1 ] || fail "yq cannot read YAML"
    gitleaks version | grep -q "$GITLEAKS_VERSION" || fail "gitleaks is $(gitleaks version), pinned $GITLEAKS_VERSION"
    got=$(pwsh -NoProfile -NonInteractive -Command "\$PSVersionTable.PSVersion.ToString()"); [ "$got" = "$PWSH_VERSION" ] || fail "pwsh is $got, pinned $PWSH_VERSION"
    printf "cd /tmp\n" > /tmp/sc.sh
    if shellcheck -s sh -S warning /tmp/sc.sh >/dev/null 2>&1; then fail "shellcheck did not flag SC2164 (cd without || exit)"; fi
    GNUPGHOME=$(mktemp -d) gpg --batch --list-keys >/dev/null 2>&1 || fail "gpg does not run"
    echo "build.sh: python 3.12 venv writable, ansible-core $ANSIBLE_CORE_VERSION, ansible-lint $ANSIBLE_LINT_VERSION, yq $YQ_VERSION, gitleaks $GITLEAKS_VERSION, pwsh $PWSH_VERSION, shellcheck and gpg ok"'
