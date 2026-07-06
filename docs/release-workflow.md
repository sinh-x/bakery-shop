# Release Workflow

> **Purpose:** Repeatable, step-by-step procedure for cutting a new bakery-shop release.
> **Audience:** Sinh (app owner/developer)
> **Created:** 2026-07-06
> **Last Updated:** 2026-07-06
> **Source:** Distilled from the v0.7.0 release (DG-210). Follows the phase plan in `agent-teams/requirements/artifacts/2026-07-06-release-v0.7.0.md`.
> **Related:** [pre-release-checklist.md](pre-release-checklist.md), [prod-workflow.md](prod-workflow.md), [post-merge-verification-checklist.md](post-merge-verification-checklist.md), [lily-deploy.md](lily-deploy.md)

---

## When to Use This Workflow

Run this for every versioned release (e.g., `0.7.0`, `0.7.1`, `0.8.0`). Patch, minor, and major releases all follow the same six phases. Hotfixes may skip Phase 3 (build artifacts) if the change is backend-only, but every release still runs Phase 1, 2, 4, 5, and 6.

## Prerequisites

- Local clone of `bakery-shop` on `main` with `develop` (or the release branch) fully reviewed.
- `gh` CLI authenticated (per `CLAUDE.md` tool preferences).
- `nix` with the `.#flutter` shell available for the Flutter web build.
- `docker` and `docker compose` for config validation.
- SSH access to `lily` reachable for the dry-run (it runs `ssh lily id -u`).
- The deploy scripts (`scripts/deploy-lily.sh`, `scripts/lib.sh`) unchanged for this release.

## Inputs

- **Previous version** — read from `pyproject.toml` (`version = "X.Y.Z"`) and `app/pubspec.yaml` (`version: X.Y.Z+N`).
- **Target version** — decided by Sinh before starting (e.g., `0.7.0`).
- **Build number** — previous `+N` incremented by 1 (e.g., `+78` → `+79`).

## Branch Strategy

All release work happens on a `release/vX.Y.Z` branch cut from `develop`. The branch is merged into `main` with a non-fast-forward merge commit (matches the prior pattern at `5b3f1d8`). Do not work directly on `main` or `develop`.

---

## Phase 1 — Version Bump + CHANGELOG

**Branch:** `release/vX.Y.Z` (created from `develop`)

1. Bump version in `pyproject.toml`:
   ```bash
   # from: version = "0.6.13"
   # to:   version = "0.7.0"
   ```
2. Bump version + build number in `app/pubspec.yaml`:
   ```yaml
   # from: version: 0.6.13+78
   # to:   version: 0.7.0+79
   ```
3. Update `CHANGELOG.md`:
   - Add a `## [X.Y.Z] — YYYY-MM-DD` section.
   - List every merged PR and direct-merge feature since the last release.
   - Reconstruct entries from `git log --oneline <last-tag>..HEAD` when prior bumps are missing.
4. Commit:
   ```bash
   git commit -m "feat(release): phase 1 - version bump X.Y.Z-1→X.Y.Z + CHANGELOG vX.Y.Z-1–vX.Y.Z"
   ```

**Verification:**
- `grep '^version = ' pyproject.toml` shows the new version.
- `grep '^version:' app/pubspec.yaml` shows the new version + build number.
- Manual review of `CHANGELOG.md` entries against `git log`.

**Traceability:** FR1, FR2; AC1, AC2.

---

## Phase 2 — Verification (Tests + Lint + Analyze)

**Branch:** `release/vX.Y.Z`

Run every CI-equivalent check before the merge. Mirrors `.github/workflows/ci.yml`.

1. Backend tests:
   ```bash
   python -m pytest tests -v
   ```
   - Must exit 0 with zero failures.
2. Backend lint gate:
   ```bash
   python -m ruff check src tests --select E9,F63,F7,F82
   ```
   - Must print `All checks passed!`.
3. Flutter analyze:
   ```bash
   cd app && flutter analyze
   ```
   - Must report `No issues found!`.
4. Flutter tests with coverage:
   ```bash
   cd app && flutter test --coverage
   ```
   - Must exit 0; `app/coverage/lcov.info` regenerated.

**Do not commit** unless a check fails and a fix is needed — verification phase produces no commits when green. If a check fails, fix on the release branch and re-run all checks before proceeding.

**Traceability:** FR6, NFR1, NFR4; AC6.

---

## Phase 3 — Build Artifacts

**Branch:** `release/vX.Y.Z`

1. Flutter web build (release) via the nix shell:
   ```bash
   nix develop ./.#flutter --command bash -c \
     "cd app && flutter build web --release --dart-define=BAKER_BUILD_FINGERPRINT=$(git rev-parse --short HEAD)"
   ```
2. Sync build output to `web-build/`:
   ```bash
   rsync -a --delete app/build/web/ web-build/
   ```
3. (Optional) Android APK — skip if Android SDK is unavailable:
   ```bash
   cd app && flutter build apk --release
   ```
   - APK is the secondary release path; web deploy is primary. Document the skip in the release ticket if omitted.
4. Validate Docker compose prod config:
   ```bash
   docker compose --profile prod config
   ```
   - Must exit 0 with valid YAML output (caddy + backend services).

`web-build/` is gitignored — it is rebuilt each release and rsynced to lily by `deploy-lily.sh`. Do not commit `web-build/`.

**Verification:**
- `ls web-build/index.html` exists.
- `docker compose --profile prod config` exits 0.

**Traceability:** FR7, FR9, NFR2; AC7, AC8, AC9.

---

## Phase 4 — Merge to main + Tag + GitHub Release

**Branch:** switch to `main` (this is the only phase that touches `main`)

1. Ensure `main` is up to date and on `main`:
   ```bash
   git checkout main && git pull
   ```
2. Merge the release branch with a non-fast-forward merge commit:
   ```bash
   git merge --no-ff release/vX.Y.Z -m "Merge release/vX.Y.Z into main: DG-<ticket> vX.Y.Z release (N commits since vX.Y.Z-1)"
   ```
3. Push `main`:
   ```bash
   git push origin main
   ```
4. Create an annotated tag pointing at the merge commit:
   ```bash
   git tag -a vX.Y.Z -m "Release vX.Y.Z" <merge-commit-sha>
   git push origin vX.Y.Z
   ```
5. Create the GitHub release with the CHANGELOG section as the body:
   ```bash
   gh release create vX.Y.Z --title "vX.Y.Z" --notes-file <(awk '/## \[X.Y.Z\]/{f=1} /## \[/{if(f && $2!="[X.Y.Z]") exit} f' CHANGELOG.md)
   ```
   - Alternatively, paste the matching `## [X.Y.Z] — …` section of `CHANGELOG.md` into `--notes`.

**Verification:**
- `git log --oneline main..develop` returns empty (or `main..release/vX.Y.Z` empty).
- `git tag --list 'vX.Y.Z'` shows the tag.
- `gh release view vX.Y.Z` shows the published release with CHANGELOG body.

**Traceability:** FR3, FR4, FR5; AC3, AC4, AC5.

---

## Phase 5 — Deploy Verification + Documentation

**Branch:** `main` (must be checked out — `deploy-lily.sh` refuses to run from another branch unless `--force`)

1. Run the deploy dry-run:
   ```bash
   ./scripts/deploy-lily.sh --dry-run
   ```
   - Must exit 0. The dry-run prints every step without mutating lily; it still calls `ssh lily id -u` to resolve the remote UID, so lily must be reachable.
2. Confirm `docs/release-workflow.md` is up to date for this release (this document). Update if the deploy script flags, printer config, or release branch pattern changed.

**Verification:**
- `./scripts/deploy-lily.sh --dry-run` completes with `=== Deploy complete ===` and exit 0.
- `docs/release-workflow.md` exists and describes the current process.

**Traceability:** FR10, FR11; AC10, AC12.

---

## Phase 6 — Deploy to lily

**Branch:** `main`

1. Run the real deploy:
   ```bash
   ./scripts/deploy-lily.sh
   ```
   - This rsyncs `docker-compose.yml`, `Dockerfile`, `docker-entrypoint.sh`, `Caddyfile`, `pyproject.toml`, `src/`, `config/`, `scripts/`, and `web-build/` to `lily:/home/sinh/bakery-shop/`, rebuilds the `baker-prod` image, restarts containers, runs the health check with retry, verifies the deployed version, and logs the deploy.
2. Health check (the script runs this automatically; verify manually too):
   ```bash
   curl -sf --max-time 10 http://lily:2108/api/health
   ```
   - Must return `{"status":"ok", ...}` with the `version` field matching `pyproject.toml`.
3. If the release includes new DB migrations, run the post-deploy DB update:
   ```bash
   ssh lily 'cd /home/sinh/bakery-shop && ./scripts/prod-update.sh'
   ```
   - See `docs/prod-workflow.md` for the full migration procedure and `docs/post-merge-verification-checklist.md` for post-migration verification.
4. Run the [pre-release-checklist.md](pre-release-checklist.md) against the deployed app (critical form fields, end-to-end order create/edit flow).

**Verification:**
- `./scripts/deploy-lily.sh` exits 0 with `=== Deploy complete ===`.
- `curl http://lily:2108/api/health` returns `{"status":"ok"}`.
- Deployed `/api/health` `version` matches `pyproject.toml`.

**Traceability:** FR (deploy); AC11.

---

## Rollback

If the deploy fails or production breaks:

```bash
./scripts/deploy-lily.sh --rollback
```

- Restores the previous `web-build/` snapshot (`web-build.prev`).
- Rebuilds the Docker image with the current fingerprint.
- Restarts containers and runs the health check.
- Logs a `rollback` entry to `deploy-history/deploy-history.log` on lily.

Note: rollback swaps `web-build/` only; the backend image is rebuilt with the current commit. A transient client/server fingerprint mismatch can appear until a subsequent normal deploy re-aligns both artifacts. See `docs/migration-rollback.md` for DB migration rollback.

---

## Checklist Summary

Run this quick checklist at the end of every release. Each item maps to a phase above.

- [ ] Phase 1 — Version bumped in `pyproject.toml` + `app/pubspec.yaml`; `CHANGELOG.md` updated
- [ ] Phase 2 — `pytest`, `ruff`, `flutter analyze`, `flutter test --coverage` all pass
- [ ] Phase 3 — `flutter build web --release` succeeds; `web-build/index.html` exists; `docker compose --profile prod config` valid
- [ ] Phase 4 — Merge commit on `main`; tag `vX.Y.Z` pushed; `gh release view vX.Y.Z` published
- [ ] Phase 5 — `./scripts/deploy-lily.sh --dry-run` exits 0; `docs/release-workflow.md` current
- [ ] Phase 6 — `./scripts/deploy-lily.sh` exits 0; `curl http://lily:2108/api/health` returns `ok`; `prod-update.sh` run if migrations present; pre-release checklist signed off

## Version History

| Date | Change | Author |
|------|--------|--------|
| 2026-07-06 | Initial version — distilled from v0.7.0 release (DG-210) | builder/team-manager |