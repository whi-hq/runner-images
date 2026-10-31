# ci-runner-infra: a GitHub Actions runner image for infrastructure-as-code repositories.
#
# Upstream's ghcr.io/actions/actions-runner is a bare runner: Ubuntu 24.04, git, curl, jq,
# the runner binary. An Ansible/Kubernetes-manifest lint job on it installs Python tooling,
# linters and a PowerShell at job time. This bakes them in at pinned versions:
#   - Python 3.12 (Ubuntu's) with a virtualenv at /opt/venv, first on PATH and owned by the
#     runner user, holding ansible-core and ansible-lint. The venv is writable on purpose: a
#     workflow that `pip install`s its own pins finds them already satisfied (a no-op), or
#     upgrades in place when it pins newer ones, so the repository stays the source of truth.
#   - yq, gitleaks (both sha256-verified release binaries), shellcheck and gnupg (Ubuntu).
#   - PowerShell 7 LTS from the official release tarball (sha256-verified).
# Ansible collections are deliberately NOT baked: a workflow that installs exactly its
# declared collections at job time is a buildability test, and a baked set would mask an
# undeclared one.
#
# Build with build.sh, never `docker build` directly: it supplies the pins from versions.env
# and proves the result offline as the runner user.
ARG RUNNER_VERSION
FROM ghcr.io/actions/actions-runner:${RUNNER_VERSION}

ARG ANSIBLE_CORE_VERSION
ARG ANSIBLE_LINT_VERSION
ARG YQ_VERSION
ARG YQ_SHA256
ARG GITLEAKS_VERSION
ARG GITLEAKS_SHA256
ARG PWSH_VERSION
ARG PWSH_SHA256

USER root
ENV DEBIAN_FRONTEND=noninteractive
ENV POWERSHELL_TELEMETRY_OPTOUT=1 POWERSHELL_UPDATECHECK=Off DOTNET_CLI_TELEMETRY_OPTOUT=1

RUN set -eu; \
    apt-get update; \
    apt-get install -y --no-install-recommends python3 python3-venv shellcheck gnupg libicu74 less; \
    rm -rf /var/lib/apt/lists/*

RUN set -eu; \
    : "${YQ_VERSION:?}" "${YQ_SHA256:?}" "${GITLEAKS_VERSION:?}" "${GITLEAKS_SHA256:?}" "${PWSH_VERSION:?}" "${PWSH_SHA256:?}"; \
    curl -fsSL --retry 3 -o /tmp/yq "https://github.com/mikefarah/yq/releases/download/v$YQ_VERSION/yq_linux_amd64"; \
    echo "$YQ_SHA256  /tmp/yq" | sha256sum -c -; \
    install -m 0755 /tmp/yq /usr/local/bin/yq; \
    curl -fsSL --retry 3 -o /tmp/gitleaks.tgz "https://github.com/gitleaks/gitleaks/releases/download/v$GITLEAKS_VERSION/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"; \
    echo "$GITLEAKS_SHA256  /tmp/gitleaks.tgz" | sha256sum -c -; \
    tar -xzf /tmp/gitleaks.tgz -C /usr/local/bin gitleaks; \
    curl -fsSL --retry 3 -o /tmp/pwsh.tgz "https://github.com/PowerShell/PowerShell/releases/download/v$PWSH_VERSION/powershell-$PWSH_VERSION-linux-x64.tar.gz"; \
    echo "$PWSH_SHA256  /tmp/pwsh.tgz" | sha256sum -c -; \
    mkdir -p /opt/microsoft/powershell/7; \
    tar -xzf /tmp/pwsh.tgz -C /opt/microsoft/powershell/7; \
    chmod +x /opt/microsoft/powershell/7/pwsh; \
    ln -s /opt/microsoft/powershell/7/pwsh /usr/local/bin/pwsh; \
    rm -f /tmp/yq /tmp/gitleaks.tgz /tmp/pwsh.tgz

RUN set -eu; \
    : "${ANSIBLE_CORE_VERSION:?}" "${ANSIBLE_LINT_VERSION:?}"; \
    python3 -m venv /opt/venv; \
    /opt/venv/bin/pip install --no-cache-dir "ansible-core==$ANSIBLE_CORE_VERSION" "ansible-lint==$ANSIBLE_LINT_VERSION"; \
    chown -R runner:docker /opt/venv
ENV PATH=/opt/venv/bin:$PATH

USER runner
