import os
from pathlib import Path

import pytest


@pytest.fixture(autouse=True)
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
    """api_client variant with AUTH_REQUIRED=true for middleware tests."""
    from unittest.mock import patch

    with patch("baker.api.middleware.AUTH_REQUIRED", True):
        yield api_client


@pytest.fixture
def anon_client(api_client):
    """api_client variant with AUTH_REQUIRED=false (grace period, default)."""
    from unittest.mock import patch

    with patch("baker.api.middleware.AUTH_REQUIRED", False):
        yield api_client
