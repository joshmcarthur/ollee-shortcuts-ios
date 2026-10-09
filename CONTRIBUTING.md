# Contributing

Keep PRs tiny. Stack a PR on its predecessor when the work depends on that branch.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`, `ci:`.

## Review bar

- No third-party Swift packages.
- No extra screens, wrappers, or types that do not carry a load.
- `OlleeFrames` stays pure Swift and covered by `swift test`.
- PR body: short prose covering what, why, and how. Headings only if they help.

## Merge

Squash merge into `main` once CI is green.
