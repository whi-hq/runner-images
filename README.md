# runner-images

Container images for self-hosted GitHub Actions runners, built on
[`ghcr.io/actions/actions-runner`](https://github.com/actions/runner) and intended for
[actions-runner-controller](https://github.com/actions/actions-runner-controller) runner scale sets.
Each image bakes in what its jobs would otherwise download on every run.

| Image | Contents |
|---|---|
| [`ghcr.io/whi-hq/ci-runner-node`](ci-runner-node/) | Node 24 in the runner tool cache (`actions/setup-node` finds it), pnpm, Chromium and its system libraries for Playwright |
| [`ghcr.io/whi-hq/ci-runner-infra`](ci-runner-infra/) | Python 3.12 with ansible-core and ansible-lint in a runner-writable venv, yq, shellcheck, gitleaks, gnupg, PowerShell 7 LTS. Ansible collections are not baked: install them at job time |

## Tags

`<UTC yyyymmddHHMMSS>-<commit sha7>`, e.g. `20261031120000-abc1234`. There is no `latest`:
pin a tag, and let an image-update tool order on the timestamp.

## Builds

Every image directory has a `Dockerfile`, a `versions.env` with every pin, and a `build.sh` that
builds from those pins and then **proves the image offline** (no network, as the runner user)
before anything is pushed. CI and a local build run the same script:

```sh
ci-runner-node/build.sh ci-runner-node:local
```

Images rebuild weekly for base-image security updates, and on any change to their directory.
Pull requests build and prove without credentials; only `main` publishes.

## Using it with actions-runner-controller

```yaml
template:
  spec:
    containers:
      - name: runner
        image: ghcr.io/whi-hq/ci-runner-node:<tag>
        command: ["/home/runner/run.sh"]
        env:
          - name: HOME
            value: /home/runner
```

The image runs as the upstream `runner` user (uid 1001) and needs no privileges.

## License

MIT
