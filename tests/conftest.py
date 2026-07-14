import os
from pathlib import Path

import pytest

# DG-029 Post-UAT Follow-up Item 1: lower bcrypt work factor in TEST only so the
# full backend suite completes well under CI's 10-min timeout-minutes cap.
# Production default stays 12 (NFR4) — this override is set before importing
# baker so baker.config.reload() picks it up on first import. Must be set at
# module top (not in a fixture) because the CryptContext instances in auth.py,
# commands/user.py, and db/schema.py read BCRYPT_ROUNDS at import time.
os.environ.setdefault("BAKER_BCRYPT_ROUNDS", "4")


# ---------------------------------------------------------------------------
# Shared autouse fixture (DG-029 Phase 5.6-c3 / CQ-2)
#
# ``_reset_auth`` was previously duplicated as an autouse fixture across
# test_rbac.py, test_actor_derivation.py, test_audit_log_api.py,
# test_auth.py, and test_user_session_cli.py. Centralizing it here means
# modules that no longer redefine it still get auth state cleared between
# tests. Modules that still redefine it (test_auth.py,
# test_user_session_cli.py, test_audit_log_api.py) keep their local
# definition, which shadows this one per pytest's fixture resolution —
# behavior unchanged for them.
# ---------------------------------------------------------------------------


@pytest.fixture(autouse=True)
def _reset_auth():
    """Clear in-memory auth state before and after each test."""
    from baker.api.auth import _reset_auth_state

    _reset_auth_state()
    yield
    _reset_auth_state()


@pytest.fixture
def use_memory_db(tmp_path, monkeypatch):
    """Use a temp file DB for each test and isolated photos dir."""
    db_path = str(tmp_path / "test.db")
    photos_dir = tmp_path / "photos"
    monkeypatch.setenv("BAKER_DB", db_path)
    # Patch config module
    import baker.config
    baker.config.DB_PATH = Path(db_path)
    baker.config.DATA_DIR = tmp_path
    baker.config.PHOTOS_DIR = photos_dir
    baker.config.LOG_DIR = tmp_path / "logs"
    baker.config.LOG_LEVEL = "INFO"
    yield db_path


@pytest.fixture
def api_client(use_memory_db):
    """FastAPI TestClient with initialized DB schema."""
    from starlette.testclient import TestClient
    from baker.api.app import create_app
    from baker.db.connection import get_db
    from baker.db.schema import ensure_schema

    with get_db() as conn:
        ensure_schema(conn)

    app = create_app()
    with TestClient(app) as client:
        yield client


@pytest.fixture
def auth_client(api_client):
    """api_client with AUTH_REQUIRED=true (patches both middleware + auth).

    Both ``baker.api.middleware.AUTH_REQUIRED`` (the gate the middleware
    reads) and ``baker.api.auth.AUTH_REQUIRED`` (the gate ``RequireRole``
    reads) are patched so role checks and actor derivation see the enforced
    mode consistently. The previous conftest version only patched
    middleware, which left ``RequireRole`` evaluating the grace-period
    branch; the per-module redefinitions in test_rbac/test_actor_derivation
    patched both, and that is the correct behavior, so it is centralized
    here.
    """
    from unittest.mock import patch

    with patch("baker.api.middleware.AUTH_REQUIRED", True):
        with patch("baker.api.auth.AUTH_REQUIRED", True):
            yield api_client


@pytest.fixture
def anon_client(api_client):
    """api_client with AUTH_REQUIRED=false (grace period, default).

    Patches both middleware and auth so the grace-period branches align
    across the request gate and ``RequireRole``.
    """
    from unittest.mock import patch

    with patch("baker.api.middleware.AUTH_REQUIRED", False):
        with patch("baker.api.auth.AUTH_REQUIRED", False):
            yield api_client