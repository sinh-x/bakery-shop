import os
import pytest


@pytest.fixture(autouse=True)
def use_memory_db(tmp_path, monkeypatch):
    """Use a temp file DB for each test."""
    db_path = str(tmp_path / "test.db")
    monkeypatch.setenv("BAKER_DB", db_path)
    # Re-import config to pick up new env var
    import baker.config
    baker.config.DB_PATH = type(baker.config.DB_PATH)(db_path)
    yield db_path
