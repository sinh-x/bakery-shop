import logging
import sqlite3
from contextlib import contextmanager

logger = logging.getLogger("baker.db")


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


def checkpoint_wal(db_path=None):
    """Flush WAL journal into main DB file before shutdown."""
    import baker.config
    path = db_path or str(baker.config.DB_PATH)
    if path == ":memory:":
        return
    try:
        conn = sqlite3.connect(path)
        conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        conn.close()
        logger.info("WAL checkpoint completed for %s", path)
    except Exception:
        logger.exception("WAL checkpoint failed for %s", path)
