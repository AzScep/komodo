# AzScep fork patches

This fork carries a small patch set on top of an upstream Komodo release.
Branch `azscep/<major>.<minor>.x` is based on the upstream tag named in `.github/workflows/azscep-periphery-image.yml` (`UPSTREAM_VERSION`).
`main` tracks `moghtech/komodo` unchanged.

To move to a new upstream release, branch from the new tag, cherry-pick each patch below, run the Periphery tests, and bump `UPSTREAM_VERSION` and reset `FORK_REVISION`.
Drop a patch as soon as upstream ships an equivalent fix.

## Carried patches

| Patch | Upstream issue | Component | Status upstream |
| --- | --- | --- | --- |
| Redact env_file secrets from stored compose config | moghtech/komodo#1636 | Periphery | Proposed in moghtech/komodo#1644 |

## Published images

`ghcr.io/azscep/komodo-periphery:<upstream-version>-azscep.<revision>` is built from this branch by `.github/workflows/azscep-periphery-image.yml`.
Deploy it by digest, alongside the upstream Core image of the same upstream version.
