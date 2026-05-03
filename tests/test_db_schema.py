from baker.db.connection import get_db
from baker.db.schema import MIGRATIONS, PRINT_LOG_AND_PRINTED_BY_SCHEMA, ensure_schema


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
        _migrate_to_version(conn, 30)
        assert _migrated_version(conn) == 30
        _assert_product_price_chips_schema(conn)


def test_schema_migration_v29_to_v30():
    with get_db() as conn:
        _migrate_to_version(conn, 29)
        assert _migrated_version(conn) == 29

        _migrate_to_version(conn, 30)
        assert _migrated_version(conn) == 30
        _assert_product_price_chips_schema(conn)


def test_schema_migration_v30_idempotent():
    with get_db() as conn:
        _migrate_to_version(conn, 29)
        _migrate_to_version(conn, 30)
        assert _migrated_version(conn) == 30

        _migrate_to_version(conn, 30)
        assert _migrated_version(conn) == 30
        _assert_product_price_chips_schema(conn)


def _assert_product_attribute_options_schema(conn) -> None:
    columns = _schema_columns(conn, "product_attribute_options")
    assert set(columns) >= {
        "id",
        "attribute_id",
        "value_vi",
        "sort_order",
        "active",
    }
    for name in ["attribute_id", "value_vi", "sort_order", "active"]:
        assert columns[name]["notnull"] == 1

    fk_rows = conn.execute(
        "PRAGMA foreign_key_list(product_attribute_options)"
    ).fetchall()
    assert len(fk_rows) == 1
    fk = fk_rows[0]
    assert fk["table"] == "product_attributes"
    assert fk["from"] == "attribute_id"
    assert fk["to"] == "id"
    assert fk["on_delete"] == "CASCADE"

    index_rows = conn.execute(
        "PRAGMA index_list(product_attribute_options)"
    ).fetchall()
    index_names = [row["name"] for row in index_rows]
    assert "idx_attr_options_attr" in index_names


def _assert_print_tracking_schema(conn) -> None:
    orders = _schema_columns(conn, "orders")
    assert "work_ticket_printed_by" in orders

    print_log = _schema_columns(conn, "print_log")
    assert set(print_log) >= {
        "id",
        "order_id",
        "item_id",
        "receipt_type",
        "printed_by",
        "printed_at",
    }

    index_rows = conn.execute("PRAGMA index_list(print_log)").fetchall()
    index_names = [row["name"] for row in index_rows]
    assert "idx_print_log_order" in index_names


def _assert_nhan_banh_seed(conn) -> None:
    attr_row = conn.execute(
        "SELECT id, label_vi, value_type, applicable_categories, default_value, active "
        "FROM product_attributes WHERE attribute_type = 'nhan_banh'"
    ).fetchone()
    assert attr_row is not None
    assert attr_row["label_vi"] == "Nhân bánh"
    assert attr_row["value_type"] == "enum"
    assert attr_row["applicable_categories"] == '["banh_kem"]'
    assert attr_row["active"] == 1
    assert attr_row["default_value"] != ""

    options = conn.execute(
        "SELECT id, value_vi, sort_order, active "
        "FROM product_attribute_options WHERE attribute_id = ? "
        "ORDER BY sort_order",
        (attr_row["id"],),
    ).fetchall()
    assert len(options) == 5
    assert all(opt["active"] == 1 for opt in options)
    assert [opt["value_vi"] for opt in options] == [
        "Sầu riêng",
        "Sô-cô-la",
        "Việt quất",
        "Chanh dây",
        "Dâu",
    ]

    default_id = int(attr_row["default_value"])
    default_match = next(opt for opt in options if opt["id"] == default_id)
    assert default_match["value_vi"] == "Sầu riêng"


def test_schema_migration_v31_fresh_db():
    with get_db() as conn:
        ensure_schema(conn)
        assert _migrated_version(conn) == 32
        _assert_product_attribute_options_schema(conn)
        _assert_nhan_banh_seed(conn)
        _assert_print_tracking_schema(conn)


def test_schema_migration_v30_to_v31():
    with get_db() as conn:
        _migrate_to_version(conn, 30)
        assert _migrated_version(conn) == 30

        ensure_schema(conn)
        assert _migrated_version(conn) == 32
        _assert_product_attribute_options_schema(conn)
        _assert_nhan_banh_seed(conn)
        _assert_print_tracking_schema(conn)


def test_schema_migration_v31_idempotent():
    with get_db() as conn:
        ensure_schema(conn)
        assert _migrated_version(conn) == 32

        ensure_schema(conn)
        assert _migrated_version(conn) == 32

        attr_count = conn.execute(
            "SELECT COUNT(*) FROM product_attributes WHERE attribute_type = 'nhan_banh'"
        ).fetchone()[0]
        assert attr_count == 1

        attr_id = conn.execute(
            "SELECT id FROM product_attributes WHERE attribute_type = 'nhan_banh'"
        ).fetchone()[0]
        opt_count = conn.execute(
            "SELECT COUNT(*) FROM product_attribute_options WHERE attribute_id = ?",
            (attr_id,),
        ).fetchone()[0]
        assert opt_count == 5
        _assert_print_tracking_schema(conn)


def test_schema_migration_v32_handles_preexisting_printed_by_column():
    with get_db() as conn:
        _migrate_to_version(conn, 31)
        conn.execute("ALTER TABLE orders ADD COLUMN work_ticket_printed_by TEXT DEFAULT ''")
        _migrate_to_version(conn, 32)

        assert _migrated_version(conn) == 32
        _assert_print_tracking_schema(conn)


def test_schema_migration_v32_sql_block_does_not_readd_orders_column():
    assert "ALTER TABLE orders ADD COLUMN work_ticket_printed_by" not in PRINT_LOG_AND_PRINTED_BY_SCHEMA
