<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Versioning

`deck.toml` `package.version` is the deck's only version, authored and
committed. jvc reads it, and `pack.sh` names the archive after it. The deck
exports no version constant.

`deck.toml` has to be committed because jvc resolves against the manifest on
the default branch: `package.urls.deck` points at
`raw.githubusercontent.com/.../main/deck.toml`. A version that existed only
inside a CI workspace would leave jvc resolving whatever was last committed.

## Releasing

1. Bump `version` in `deck.toml` and commit it.
2. Tag the same number: `git tag 0.2.0` (no `v` prefix) and push it.

`release.yml` refuses a tag that disagrees with the manifest, and one
carrying a prerelease suffix (`0.3.0-rc1`).

## CI

| Workflow | Trigger | Does |
|---|---|---|
| `test.yml` | every commit, every branch, every PR | fmt, lint, guards, suites, examples, `jennifer-tiny` |
| `docs.yml` | release tag, push to `main`, PR | Grimoire's shared Pages workflow: publish the book of the highest release tag (`main` before the first); a PR only builds |
| `release.yml` | stable version tag | the same gate, then pack and release |
