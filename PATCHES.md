# AzScep fork patches

This fork carries a small patch set on top of an upstream Komodo release.
Branch `azscep/<major>.<minor>.x` is based on the upstream tag named in `.github/workflows/azscep-images.yml` (`UPSTREAM_VERSION`).
`main` tracks `moghtech/komodo` unchanged.

To move to a new upstream release, branch from the new tag, cherry-pick each patch below, run the tests in `.github/workflows/azscep-images.yml`, and bump `UPSTREAM_VERSION` and reset `FORK_REVISION`.
Drop a patch as soon as upstream ships an equivalent fix.

## Carried patches

| Patch | Upstream issue | Component | Status upstream |
| --- | --- | --- | --- |
| Redact env_file secrets from stored compose config | moghtech/komodo#1636 | Periphery | Proposed in moghtech/komodo#1644 |
| Send extra websocket headers to Core from a root-only file (`core_headers_file`) | None | Periphery | Proposed in moghtech/komodo#1649 |
| `Restart` specific permission: `RestartStack` with Read + Restart, without Execute | None | Core, client, UI | Proposed in moghtech/komodo#1650 |

## Published images

`ghcr.io/azscep/komodo-core:<upstream-version>-azscep.<revision>` and `ghcr.io/azscep/komodo-periphery:<upstream-version>-azscep.<revision>` are built from this branch by `.github/workflows/azscep-images.yml`.
Deploy both by digest, at the same tag.
Revisions 1 and 2 carried only Periphery patches and published only Periphery.
