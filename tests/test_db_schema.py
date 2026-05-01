from baker.db.connection import get_db
from baker.db.schema import MIGRATIONS, ensure_schema


def _migrate_to_version(conn, target_version: int) -> None:
    """Apply migrations incrementally up to target_version (inclusive)."""
    row = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_version'"
    ).fetchone()
    current_version = 0
    if row:
        current_row = conn.execute("SELECT MAX(version) FROM schema_version").fetchone()
        current_version = current_row[0] if current_row and current_row[0] is not None else 0
    for version in sorted(MIGRATIONS.keys()):
        if version <= current_version or version > target_version:
            continue
        conn.executescript(MIGRATIONS[version]["sql"])

        seed = MIGRATIONS[version].get("seed")
        if seed:
            for name, category, base_price, cost, recipe_notes in seed:
                conn.execute(
                    "INSERT OR IGNORE INTO products "
                    "(name, category, base_price, cost, recipe_notes) "
                    "VALUES (?, ?, ?, ?, ?)",
                    (name, category, base_price, cost, recipe_notes),
                )

        callable_fn = MIGRATIONS[version].get("callable")
        if callable_fn:
            callable_fn(conn)

        conn.execute(
            "INSERT INTO schema_version (version, description) VALUES (?, ?)",
            (version, MIGRATIONS[version]["description"]),
        )
    conn.commit()


def _schema_columns(conn, table: str) -> dict[str, tuple]:
    return {
        row["name"]: row
        for row in conn.execute(f"PRAGMA table_info({table})").fetchall()
    }


def _assert_product_price_chips_schema(conn) -> None:
    columns = _schema_columns(conn, "product_price_chips")
    assert set(columns) >= {
        "id",
        "product_id",
        "label",
        "price",
        "position",
        "created_at",
    }
    for name in ["product_id", "label", "price", "position", "created_at"]:
        assert columns[name]["notnull"] == 1

    fk_rows = conn.execute("PRAGMA foreign_key_list(product_price_chips)").fetchall()
    assert len(fk_rows) == 1
    fk = fk_rows[0]
    assert fk["table"] == "products"
    assert fk["from"] == "product_id"
    assert fk["to"] == "id"
    assert fk["on_delete"] == "CASCADE"

    index_rows = conn.execute("PRAGMA index_list(product_price_chips)").fetchall()
    index_names = [row["name"] for row in index_rows]
    assert "idx_product_price_chips_product" in index_names
    index_info = conn.execute(
        "PRAGMA index_info(idx_product_price_chips_product)"
    ).fetchall()
    index_columns = [row["name"] for row in index_info]
    assert index_columns == ["product_id"]


def _migrated_version(conn) -> int:
    row = conn.execute("SELECT MAX(version) FROM schema_version").fetchone()
    return int(row[0] or 0)


def test_schema_migration_v30_fresh_db():
    with get_db() as conn:
        ensure_schema(conn)
        assert _migrated_version(conn) == 30
        _assert_product_price_chips_schema(conn)


def test_schema_migration_v29_to_v30():
    with get_db() as conn:
        _migrate_to_version(conn, 29)
        assert _migrated_version(conn) == 29

        ensure_schema(conn)
        assert _migrated_version(conn) == 30
        _assert_product_price_chips_schema(conn)


def test_schema_migration_v30_idempotent():
    with get_db() as conn:
        _migrate_to_version(conn, 29)
        ensure_schema(conn)
        assert _migrated_version(conn) == 30

        ensure_schema(conn)
        assert _migrated_version(conn) == 30
        _assert_product_price_chips_schema(conn)
