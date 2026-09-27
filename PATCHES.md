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
| `age` and `komodo-age-decrypt` in the Periphery image, for age-encrypted stack secrets | None | Periphery image | Fork only: it serves our own config design |

## Published images

`ghcr.io/azscep/komodo-core:<upstream-version>-azscep.<revision>` and `ghcr.io/azscep/komodo-periphery:<upstream-version>-azscep.<revision>` are built from this branch by `.github/workflows/azscep-images.yml`.
Deploy both by digest, at the same tag.
Revisions 1 and 2 carried only Periphery patches and published only Periphery.

## Decrypting stack secrets

From revision 4 the Periphery image carries Debian's `age` and `/usr/local/bin/komodo-age-decrypt` ([source](bin/periphery/komodo-age-decrypt), [tests](bin/periphery/tests/komodo-age-decrypt.test.sh)).
A stack keeps each secret in its `environment` as `AGE_<NAME>=<base64 age ciphertext>`, sets `additional_env_files` to `[{path: secrets.env, track: false}]`, and runs `komodo-age-decrypt .env secrets.env` as its `pre_deploy`.
The script decrypts every secret with the server's age identity and writes `NAME='value'` lines to `secrets.env` with mode 0600, replacing the file only when every secret decrypted.
It exits non-zero, so the deploy stops before `compose up`, when a secret fails to decrypt, is listed twice, shares its name with a plain setting or a variable in Periphery's environment, holds a single quote, a line break, or another control character, or ends in a backslash.
Every `environment` line starting `AGE_` is taken as a secret, so a plain setting must not use that prefix.
It prints secret names, never values.

Mount the server's age identity read-only at `/config/age.key` (or set `KOMODO_AGE_IDENTITY`); the script refuses an identity readable by group or others.
