# Bakery Shop Developer Notes

## Project Structure

- `src/baker/`: Python backend package (FastAPI API, services, config, logging, CLI).
- `tests/`: Python backend tests (API + service behavior).
- `app/`: Flutter client app.
- `.github/workflows/ci.yml`: CI for Python, Flutter, and Docker checks.
- `docker-compose.yml`: Local/prod compose topology for backend + Caddy.

## Common Commands

- Backend tests: `python -m pytest tests -v`
- Backend lint gate used in CI: `python -m ruff check src tests --select E9,F63,F7,F82`
- Compose prod config validation: `docker compose --profile prod config`
- Flutter analyze: `cd app && flutter analyze`
- Dart analyze: `cd app && dart analyze`
- Flutter tests with coverage: `cd app && flutter test --coverage`

## VN Label Policy

- User-facing copy should prefer shared Vietnamese label/constants modules over inline strings.
- New text introduced in feature code should be centralized when the text is reused or policy-relevant.
- Keep labels consistent with existing bakery POS wording and avoid untranslated fallback strings in primary flows.

## Provider Directory Rationale

- Provider files are grouped by domain/feature to keep dependency boundaries clear.
- This separation avoids cross-feature coupling, keeps Riverpod graph intent visible, and simplifies test setup.
- Shared providers stay in shared/common directories; feature providers stay close to feature screens/services.

## Flutter Coding Standards

Future Flutter work must follow [docs/flutter-coding-standards.md](docs/flutter-coding-standards.md) for file sizing, widget extraction, provider placement, Riverpod state management, VN label organization, testing, and lint rules. The [docs/code-quality-audit.md](docs/code-quality-audit.md) catalogues pre-existing oversized files and extraction targets. DG-138 tracks the deferred const suppression audit.

## Review-Remediation Verification Expectations

- If CI/deployment/runtime files are touched, verify Python discovery tests, compose config, and package version sync.
- For Flutter CI changes, verify `flutter analyze`, `dart analyze`, and `flutter test --coverage`.
- Document exact blockers when a required command cannot run locally.
- Preserve DG-119 prior-phase baselines (upload-size limits and sanitized exception persistence).

## Runtime Requirements

- **SQLite ≥ 3.35.0**: The schema migrations in `src/baker/db/schema.py` use `ALTER TABLE ... DROP COLUMN` (e.g. the v80 drop of the stored `amount_paid` column), which is only supported by SQLite 3.35.0 and later. Any environment running the backend (local dev, CI, Docker image, production host) must provide SQLite ≥ 3.35.0 or migration execution will fail with `near "DROP": syntax error`. Verify with `python -c "import sqlite3; print(sqlite3.sqlite_version)"` (must report ≥ `3.35.0`).
