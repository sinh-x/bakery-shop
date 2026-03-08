import sqlite3
from contextlib import contextmanager


@contextmanager
def get_db(db_path=None):
    """Context manager for database connections."""
    import baker.config
    path = db_path or str(baker.config.DB_PATH)
    if path != ":memory:":
        from pathlib import Path
        Path(path).parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(path)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    conn.execute("PRAGMA foreign_keys=ON")
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
