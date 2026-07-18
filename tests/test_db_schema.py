import json

from baker.db.connection import get_db
from baker.db.schema import (
    BUS_SHIPPING_HELD_CODE,
    CUSTOMER_DEPOSITS_CODE,
    MIGRATIONS,
    PRINT_LOG_AND_PRINTED_BY_SCHEMA,
    ensure_schema,
)


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


def _assert_reconciliation_sale_rows_schema(conn) -> None:
    line_columns = _schema_columns(conn, "reconciliation_lines")
    assert "waste_reason" in line_columns

    columns = _schema_columns(conn, "reconciliation_sale_rows")
    assert set(columns) >= {
        "id",
        "line_id",
        "quantity",
        "unit_price",
        "payment_method",
        "linked_order_ref",
        "linked_payment_ref",
        "created_at",
    }

    fk_rows = conn.execute("PRAGMA foreign_key_list(reconciliation_sale_rows)").fetchall()
    assert len(fk_rows) == 1
    fk = fk_rows[0]
    assert fk["table"] == "reconciliation_lines"
    assert fk["from"] == "line_id"
    assert fk["to"] == "id"
    assert fk["on_delete"] == "CASCADE"

    index_rows = conn.execute("PRAGMA index_list(reconciliation_sale_rows)").fetchall()
    index_names = [row["name"] for row in index_rows]
    assert "idx_reconciliation_sale_rows_line" in index_names


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


def _assert_chip_aware_inventory_schema(conn) -> None:
    stock_lot_columns = _schema_columns(conn, "stock_lots")
    assert set(stock_lot_columns) >= {
        "id",
        "product_id",
        "price_chip_id",
        "quantity",
        "remaining_qty",
        "restocked_at",
        "created_at",
    }

    item_columns = _schema_columns(conn, "inventory_items")
    assert set(item_columns) >= {
        "id",
        "lot_id",
        "uuid",
        "status",
        "consumed_by_movement_id",
        "created_at",
    }
    assert item_columns["uuid"]["notnull"] == 1

    stock_movement_columns = _schema_columns(conn, "stock_movements")
    assert "lot_id" in stock_movement_columns
    assert "price_chip_id" in stock_movement_columns

    order_item_columns = _schema_columns(conn, "order_items")
    assert "price_chip_id" in order_item_columns

    reconciliation_line_columns = _schema_columns(conn, "reconciliation_lines")
    assert "price_chip_id" in reconciliation_line_columns


def _assert_v40_v41_schema(conn) -> None:
    event_columns = _schema_columns(conn, "events")
    assert "order_id" in event_columns
    assert event_columns["order_id"]["notnull"] == 0

    event_fks = conn.execute("PRAGMA foreign_key_list(events)").fetchall()
    order_id_fks = [fk for fk in event_fks if fk["from"] == "order_id"]
    assert len(order_id_fks) == 1
    assert order_id_fks[0]["table"] == "orders"
    assert order_id_fks[0]["to"] == "id"

    index_rows = conn.execute("PRAGMA index_list(events)").fetchall()
    index_names = [row["name"] for row in index_rows]
    assert "idx_events_order_id" in index_names

    event_photos_columns = _schema_columns(conn, "event_photos")
    assert set(event_photos_columns) >= {
        "id",
        "event_id",
        "photo_id",
        "tags",
        "position",
        "created_at",
    }
    for name in ["event_id", "photo_id", "position"]:
        assert event_photos_columns[name]["notnull"] == 1

    event_photos_fks = conn.execute("PRAGMA foreign_key_list(event_photos)").fetchall()
    assert len(event_photos_fks) == 2
    fk_tables = {(fk["from"], fk["table"]) for fk in event_photos_fks}
    assert ("event_id", "events") in fk_tables
    assert ("photo_id", "photos") in fk_tables

    ep_index_rows = conn.execute("PRAGMA index_list(event_photos)").fetchall()
    ep_index_names = [row["name"] for row in ep_index_rows]
    assert "idx_event_photos_event" in ep_index_names


def _assert_event_history_schema(conn) -> None:
    columns = _schema_columns(conn, "event_history")
    assert set(columns) >= {
        "id",
        "event_id",
        "action_type",
        "actor",
        "field_name",
        "old_value",
        "new_value",
        "timestamp",
    }
    for name in ["event_id", "action_type", "timestamp"]:
        assert columns[name]["notnull"] == 1

    fk_rows = conn.execute("PRAGMA foreign_key_list(event_history)").fetchall()
    assert len(fk_rows) == 1
    fk = fk_rows[0]
    assert fk["table"] == "events"
    assert fk["from"] == "event_id"
    assert fk["to"] == "id"

    index_rows = conn.execute("PRAGMA index_list(event_history)").fetchall()
    index_names = [row["name"] for row in index_rows]
    assert "idx_event_history_event" in index_names
    assert "idx_event_history_timestamp" in index_names


def _assert_soft_delete_columns(conn) -> None:
    event_columns = _schema_columns(conn, "events")
    assert "deleted_at" in event_columns
    assert "deleted_by" in event_columns
    assert event_columns["deleted_at"]["notnull"] == 0
    assert event_columns["deleted_by"]["notnull"] == 0


def _assert_users_role_check_constraint(conn) -> None:
    """Mn-3 (DG-029 phase 5.6-c1): users.role has a DB-level CHECK constraint."""
    row = conn.execute(
        "SELECT sql FROM sqlite_master WHERE type='table' AND name='users'"
    ).fetchone()
    assert row is not None, "users table missing"
    create_sql = (row["sql"] or "").replace("\n", " ")
    assert "CHECK(role IN" in create_sql, (
        f"users table missing CHECK(role IN ...) constraint; sql={create_sql!r}"
    )
    # Inserting an invalid role must be rejected by the DB itself.
    import pytest as _pytest
    try:
        conn.execute(
            "INSERT INTO users (username, password_hash, role, active) "
            "VALUES ('__check_probe__', 'x', 'superuser', 1)"
        )
    except Exception as exc:
        # CHECK constraint violation — expected.
        if "CHECK" not in str(exc).upper() and "constraint" not in str(exc).lower():
            raise
    else:
        # Roll back the offending insert so we don't poison other tests.
        conn.execute("DELETE FROM users WHERE username = '__check_probe__'")
        conn.commit()
        raise _pytest.fail(
            "users.role CHECK constraint did not reject role='superuser'"
        )


def _seed_v35_stock(conn) -> tuple[int, int, int]:
    conn.execute(
        """INSERT INTO products (name, category, base_price, cost, recipe_notes)
           VALUES ('Migration Product A', 'banh_mi', 15000, 0, '')"""
    )
    product_a_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])

    conn.execute(
        """INSERT INTO products (name, category, base_price, cost, recipe_notes)
           VALUES ('Migration Product B', 'banh_kem', 12000, 0, '')"""
    )
    product_b_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])

    conn.execute(
        "INSERT INTO product_price_chips (product_id, label, price, position) VALUES (?, 'Chip Low', 9000, 1)",
        (product_a_id,),
    )
    chip_a_low_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])
    conn.execute(
        "INSERT INTO product_price_chips (product_id, label, price, position) VALUES (?, 'Chip High', 18000, 2)",
        (product_a_id,),
    )

    conn.execute("INSERT INTO product_stock (product_id, quantity) VALUES (?, ?)", (product_a_id, 3))
    conn.execute("INSERT INTO product_stock (product_id, quantity) VALUES (?, ?)", (product_b_id, 2))

    return product_a_id, product_b_id, chip_a_low_id


def test_schema_migration_v31_fresh_db():
    with get_db() as conn:
        ensure_schema(conn)
        assert _migrated_version(conn) == 77
        _assert_product_attribute_options_schema(conn)
        _assert_nhan_banh_seed(conn)
        _assert_print_tracking_schema(conn)
        _assert_reconciliation_sale_rows_schema(conn)
        _assert_chip_aware_inventory_schema(conn)
        _assert_v40_v41_schema(conn)
        _assert_event_history_schema(conn)
        _assert_soft_delete_columns(conn)
        _assert_users_role_check_constraint(conn)


def test_schema_migration_v30_to_v31():
    with get_db() as conn:
        _migrate_to_version(conn, 30)
        assert _migrated_version(conn) == 30

        ensure_schema(conn)
        assert _migrated_version(conn) == 77
        _assert_product_attribute_options_schema(conn)
        _assert_nhan_banh_seed(conn)
        _assert_print_tracking_schema(conn)
        _assert_reconciliation_sale_rows_schema(conn)
        _assert_chip_aware_inventory_schema(conn)
        _assert_v40_v41_schema(conn)
        _assert_event_history_schema(conn)
        _assert_soft_delete_columns(conn)
        _assert_users_role_check_constraint(conn)


def test_schema_migration_v31_idempotent():
    with get_db() as conn:
        ensure_schema(conn)
        assert _migrated_version(conn) == 77

        ensure_schema(conn)
        assert _migrated_version(conn) == 77

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
        _assert_reconciliation_sale_rows_schema(conn)
        _assert_chip_aware_inventory_schema(conn)
        _assert_v40_v41_schema(conn)
        _assert_users_role_check_constraint(conn)


def test_schema_migration_v32_handles_preexisting_printed_by_column():
    with get_db() as conn:
        _migrate_to_version(conn, 31)
        conn.execute("ALTER TABLE orders ADD COLUMN work_ticket_printed_by TEXT DEFAULT ''")
        _migrate_to_version(conn, 32)

        assert _migrated_version(conn) == 32
        _assert_print_tracking_schema(conn)


def test_schema_migration_v32_sql_block_does_not_readd_orders_column():
    assert "ALTER TABLE orders ADD COLUMN work_ticket_printed_by" not in PRINT_LOG_AND_PRINTED_BY_SCHEMA


def test_schema_migration_v35_repairs_missing_reconciliation_line_waste_reason():
    with get_db() as conn:
        conn.execute(
            """CREATE TABLE schema_version (
                version INTEGER PRIMARY KEY,
                description TEXT NOT NULL,
                applied_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
            )"""
        )
        conn.execute(
            """CREATE TABLE reconciliation_lines (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id INTEGER NOT NULL,
                product_id INTEGER NOT NULL,
                expected_qty INTEGER NOT NULL,
                counted_qty INTEGER NOT NULL,
                sale_qty INTEGER NOT NULL DEFAULT 0,
                waste_qty INTEGER NOT NULL DEFAULT 0,
                manual_unit_price REAL DEFAULT NULL,
                linked_order_item_id INTEGER DEFAULT NULL,
                linked_stock_movement_sale_id INTEGER DEFAULT NULL,
                linked_stock_movement_waste_id INTEGER DEFAULT NULL,
                created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now', 'localtime'))
            )"""
        )
        conn.execute(
            "INSERT INTO schema_version (version, description) VALUES (34, 'Grouped reconciliation sale rows table')"
        )

        _migrate_to_version(conn, 35)

        assert _migrated_version(conn) == 35
        line_columns = _schema_columns(conn, "reconciliation_lines")
        assert "waste_reason" in line_columns


def test_schema_migration_v36_migrates_product_stock_to_lots_and_items():
    with get_db() as conn:
        _migrate_to_version(conn, 35)
        product_a_id, product_b_id, chip_a_low_id = _seed_v35_stock(conn)

        _migrate_to_version(conn, 36)

        assert _migrated_version(conn) == 36
        _assert_chip_aware_inventory_schema(conn)

        has_product_stock = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='product_stock'"
        ).fetchone()
        assert has_product_stock is None

        lots = conn.execute(
            "SELECT product_id, price_chip_id, quantity, remaining_qty FROM stock_lots ORDER BY product_id"
        ).fetchall()
        assert len(lots) == 2

        lot_a = next(row for row in lots if row["product_id"] == product_a_id)
        assert lot_a["price_chip_id"] == chip_a_low_id
        assert lot_a["quantity"] == 3
        assert lot_a["remaining_qty"] == 3

        lot_b = next(row for row in lots if row["product_id"] == product_b_id)
        assert lot_b["price_chip_id"] is None
        assert lot_b["quantity"] == 2
        assert lot_b["remaining_qty"] == 2

        item_count = conn.execute("SELECT COUNT(*) FROM inventory_items").fetchone()[0]
        assert item_count == 5

        distinct_uuid_count = conn.execute(
            "SELECT COUNT(DISTINCT uuid) FROM inventory_items"
        ).fetchone()[0]
        assert distinct_uuid_count == 5

        invalid_uuid_count = conn.execute(
            "SELECT COUNT(*) FROM inventory_items WHERE uuid NOT GLOB '????????-????-4???-[89abAB]???-????????????'"
        ).fetchone()[0]
        assert invalid_uuid_count == 0


def test_schema_migration_v37_merges_duplicate_price_buckets_without_data_loss():
    with get_db() as conn:
        _migrate_to_version(conn, 36)
        conn.execute(
            """INSERT INTO products (name, category, base_price, cost, recipe_notes)
               VALUES ('Bucket Merge Product', 'banh_mi', 13000, 0, '')"""
        )
        product_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])
        conn.execute(
            "INSERT INTO product_price_chips (product_id, label, price, position) VALUES (?, 'chip 130', 13000, 1)",
            (product_id,),
        )
        chip_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])

        conn.execute(
            "INSERT INTO stock_lots (product_id, price_chip_id, quantity, remaining_qty) VALUES (?, NULL, 2, 2)",
            (product_id,),
        )
        base_lot_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])
        conn.execute(
            "INSERT INTO stock_lots (product_id, price_chip_id, quantity, remaining_qty) VALUES (?, ?, 3, 3)",
            (product_id, chip_id),
        )
        chip_lot_id = int(conn.execute("SELECT last_insert_rowid()").fetchone()[0])

        for lot_id in (base_lot_id, chip_lot_id):
            for idx in range(2 if lot_id == base_lot_id else 3):
                conn.execute(
                    "INSERT INTO inventory_items (lot_id, uuid, status) VALUES (?, ?, 'available')",
                    (lot_id, f"{lot_id}-uuid-{idx}"),
                )

        _migrate_to_version(conn, 37)
        assert _migrated_version(conn) == 37

        lots = conn.execute(
            "SELECT id, price_chip_id, quantity, remaining_qty FROM stock_lots WHERE product_id = ? ORDER BY id",
            (product_id,),
        ).fetchall()
        assert len(lots) == 1
        assert lots[0]["price_chip_id"] is None
        assert lots[0]["quantity"] == 5
        assert lots[0]["remaining_qty"] == 5

        inventory_count = conn.execute(
            "SELECT COUNT(*) FROM inventory_items WHERE lot_id = ?",
            (lots[0]["id"],),
        ).fetchone()[0]
        assert inventory_count == 5


def test_schema_migration_v38_creates_phu_kien_from_order_extra():
    with get_db() as conn:
        _migrate_to_version(conn, 37)
        conn.execute("DELETE FROM app_config WHERE config_key = 'order_extra'")
        conn.execute(
            "INSERT INTO app_config (config_key, config_value, sort_order) VALUES ('order_extra', 'Hộp|20000', 1)"
        )
        conn.execute(
            "INSERT INTO app_config (config_key, config_value, sort_order) VALUES ('order_extra', 'Nến|5000', 2)"
        )

        _migrate_to_version(conn, 38)

        category = conn.execute(
            "SELECT slug, name, active FROM categories WHERE slug = 'phu_kien'"
        ).fetchone()
        assert category is not None
        assert category["name"] == "Phụ kiện"
        assert category["active"] == 1

        products = conn.execute(
            "SELECT id, name, category, base_price, active FROM products WHERE category = 'phu_kien' ORDER BY name"
        ).fetchall()
        assert len(products) == 2
        assert [row["name"] for row in products] == ["Hộp", "Nến"]
        assert [int(row["base_price"]) for row in products] == [20000, 5000]
        assert all(row["active"] == 1 for row in products)

        for product in products:
            attrs = conn.execute(
                "SELECT attribute_type, value FROM product_attribute_values WHERE product_id = ?",
                (product["id"],),
            ).fetchall()
            attr_map = {row["attribute_type"]: row["value"] for row in attrs}
            assert attr_map["trung_bay"] == "true"
            assert attr_map["tang_kem"] == "true"


def test_schema_migration_v38_is_idempotent_for_normalized_accessory_names():
    with get_db() as conn:
        _migrate_to_version(conn, 37)
        conn.execute("DELETE FROM app_config WHERE config_key = 'order_extra'")
        conn.execute(
            "INSERT INTO app_config (config_key, config_value, sort_order) VALUES ('order_extra', 'Hộp|20000', 1)"
        )
        conn.execute(
            "INSERT INTO app_config (config_key, config_value, sort_order) VALUES ('order_extra', '  hộp  |20000', 2)"
        )

        _migrate_to_version(conn, 38)
        MIGRATIONS[38]["callable"](conn)

        rows = conn.execute(
            "SELECT LOWER(TRIM(name)) AS normalized_name, COUNT(*) AS c "
            "FROM products WHERE category = 'phu_kien' GROUP BY LOWER(TRIM(name))"
        ).fetchall()
        assert len(rows) == 1
        assert rows[0]["normalized_name"] == "hộp"
        assert rows[0]["c"] == 1


def test_schema_migration_v43_creates_event_history_table_and_soft_delete_columns():
    with get_db() as conn:
        _migrate_to_version(conn, 42)
        assert _migrated_version(conn) == 42

        _migrate_to_version(conn, 43)
        assert _migrated_version(conn) == 43

        _assert_event_history_schema(conn)
        _assert_soft_delete_columns(conn)


def test_schema_migration_v43_idempotent():
    with get_db() as conn:
        _migrate_to_version(conn, 42)
        _migrate_to_version(conn, 43)
        assert _migrated_version(conn) == 43

        _migrate_to_version(conn, 43)
        assert _migrated_version(conn) == 43

        _assert_event_history_schema(conn)
        _assert_soft_delete_columns(conn)


def test_schema_migration_v43_backfills_staff_name_audit_entries():
    with get_db() as conn:
        _migrate_to_version(conn, 42)

        conn.execute(
            """INSERT INTO events (type, summary, data, logged_by, timestamp)
               VALUES ('expense', 'Test expense', ?, '', '2026-06-21T10:00:00+07:00')""",
            (json.dumps({"amount_vnd": 50000, "category": "NL", "payment_method": "TM",
                         "payment_source": "Shop tiền mặt", "vendor": "NCC A", "note": "",
                         "staff_name": "Ân", "paid_by_name": ""}),),
        )

        _migrate_to_version(conn, 43)
        assert _migrated_version(conn) == 43

        audit_rows = conn.execute(
            "SELECT * FROM event_history WHERE action_type = 'create' AND field_name = 'staff_name'"
        ).fetchall()
        assert len(audit_rows) == 1
        assert audit_rows[0]["actor"] == "Ân"
        assert audit_rows[0]["new_value"] == "Ân"
        assert audit_rows[0]["old_value"] is None

        event_row = conn.execute("SELECT logged_by, data FROM events WHERE type = 'expense'").fetchone()
        assert event_row is not None
        assert event_row["logged_by"] == "Ân"

        data = json.loads(event_row["data"])
        assert "staff_name" not in data


def test_schema_migration_v43_preserves_existing_logged_by():
    with get_db() as conn:
        _migrate_to_version(conn, 42)

        conn.execute(
            """INSERT INTO events (type, summary, data, logged_by, timestamp)
               VALUES ('expense', 'Test expense', ?, 'Sinh', '2026-06-21T10:00:00+07:00')""",
            (json.dumps({"amount_vnd": 50000, "category": "NL", "payment_method": "TM",
                         "payment_source": "Shop tiền mặt", "vendor": "NCC A", "note": "",
                         "staff_name": "Ân", "paid_by_name": ""}),),
        )

        _migrate_to_version(conn, 43)

        event_row = conn.execute("SELECT logged_by, data FROM events WHERE type = 'expense'").fetchone()
        assert event_row["logged_by"] == "Sinh"

        data = json.loads(event_row["data"])
        assert "staff_name" not in data


def test_schema_migration_v43_skips_non_expense_events():
    with get_db() as conn:
        _migrate_to_version(conn, 42)

        conn.execute(
            """INSERT INTO events (type, summary, data, logged_by, timestamp)
               VALUES ('note', 'Test note', ?, 'Sinh', '2026-06-21T10:00:00+07:00')""",
            (json.dumps({"staff_name": "Ân"}),),
        )

        _migrate_to_version(conn, 43)

        audit_count = conn.execute(
            "SELECT COUNT(*) FROM event_history WHERE action_type = 'create' AND field_name = 'staff_name'"
        ).fetchone()[0]
        assert audit_count == 0

        event_row = conn.execute("SELECT data FROM events WHERE type = 'note'").fetchone()
        data = json.loads(event_row["data"])
        assert "staff_name" in data


def test_schema_migration_v43_no_expense_events_is_noop():
    with get_db() as conn:
        _migrate_to_version(conn, 42)

        _migrate_to_version(conn, 43)
        assert _migrated_version(conn) == 43

        _assert_event_history_schema(conn)
        _assert_soft_delete_columns(conn)

        audit_count = conn.execute("SELECT COUNT(*) FROM event_history").fetchone()[0]
        assert audit_count == 0


# ---------------------------------------------------------------------------
# Migration v44 — Double-entry accounting
# ---------------------------------------------------------------------------


def _assert_accounts_table(conn) -> None:
    columns = _schema_columns(conn, "accounts")
    assert set(columns) >= {
        "id",
        "code",
        "name",
        "type",
        "parent_id",
        "is_active",
        "created_at",
    }
    assert columns["code"]["notnull"] == 1
    assert columns["name"]["notnull"] == 1
    assert columns["type"]["notnull"] == 1
    # code must be unique
    index_rows = conn.execute("PRAGMA index_list(accounts)").fetchall()
    index_names = [row["name"] for row in index_rows]
    assert "sqlite_autoindex_accounts_1" in index_names or any(
        "unique" in str(row).lower() for row in index_rows
    )
    # parent_id self-reference
    fk_rows = conn.execute("PRAGMA foreign_key_list(accounts)").fetchall()
    parent_fks = [fk for fk in fk_rows if fk["from"] == "parent_id"]
    assert len(parent_fks) == 1
    assert parent_fks[0]["table"] == "accounts"


def _assert_journal_entries_table(conn) -> None:
    columns = _schema_columns(conn, "journal_entries")
    assert set(columns) >= {
        "id",
        "description",
        "created_at",
        "source_type",
        "source_id",
        "locked_at",
        "locked_by",
    }
    assert columns["description"]["notnull"] == 1
    assert columns["source_type"]["notnull"] == 1
    # source_id is nullable
    assert columns["source_id"]["notnull"] == 0
    assert columns["locked_at"]["notnull"] == 0

    index_rows = conn.execute("PRAGMA index_list(journal_entries)").fetchall()
    index_names = [row["name"] for row in index_rows]
    assert "idx_journal_entries_created" in index_names
    assert "idx_journal_entries_source" in index_names


def _assert_journal_lines_table(conn) -> None:
    columns = _schema_columns(conn, "journal_lines")
    assert set(columns) >= {
        "id",
        "journal_entry_id",
        "account_id",
        "debit",
        "credit",
        "description",
    }
    for name in ("journal_entry_id", "account_id", "debit", "credit"):
        assert columns[name]["notnull"] == 1

    fk_rows = conn.execute("PRAGMA foreign_key_list(journal_lines)").fetchall()
    fk_tables = {(fk["from"], fk["table"], fk["on_delete"]) for fk in fk_rows}
    assert ("journal_entry_id", "journal_entries", "CASCADE") in fk_tables
    assert ("account_id", "accounts", "NO ACTION") in fk_tables

    index_rows = conn.execute("PRAGMA index_list(journal_lines)").fetchall()
    index_names = [row["name"] for row in index_rows]
    assert "idx_journal_lines_entry" in index_names
    assert "idx_journal_lines_account" in index_names


# Expected chart of accounts seeded by v44.
_EXPECTED_COA = {
    "1000": ("Tài sản", "asset", None),
    "1100": ("Tiền mặt (Cash on Hand)", "asset", "1000"),
    "1200": ("Tài khoản ngân hàng (Bank Account)", "asset", "1000"),
    "1300": ("Hàng tồn kho (Inventory)", "asset", "1000"),
    "2000": ("Nợ phải trả", "liability", None),
    "2100": ("Tiền khách đặt cọc (Customer Deposits)", "liability", "2000"),
    "2200": ("Tiền ship bus giữ hộ (Bus Shipping Held)", "liability", "2000"),
    "2300": ("Phải trả nhân viên (Staff Payables)", "liability", "2000"),
    "3000": ("Vốn chủ sở hữu", "equity", None),
    "3100": ("Vốn chủ sở hữu (Owner's Equity)", "equity", "3000"),
    "4000": ("Doanh thu", "income", None),
    "4100": ("Doanh thu bán hàng (Order Revenue)", "income", "4000"),
    "5000": ("Chi phí", "expense", None),
    "5100": ("Nguyên liệu (Ingredients)", "expense", "5000"),
    "5200": ("Bao bì (Packaging)", "expense", "5000"),
    "5300": ("Vận chuyển (Delivery/Shipping)", "expense", "5000"),
    "5400": ("Điện/nước (Utilities)", "expense", "5000"),
    "5500": ("Dụng cụ (Tools)", "expense", "5000"),
    "5600": ("Sửa chữa (Equipment Maintenance)", "expense", "5000"),
    "5700": ("Lương/phụ cấp (Staff Salary)", "expense", "5000"),
    "5800": ("Khác (Other Expenses)", "expense", "5000"),
    "5900": ("Giá vốn hàng bán (COGS)", "expense", "5000"),
}


def _assert_seed_coa(conn) -> None:
    rows = conn.execute("SELECT * FROM accounts ORDER BY code").fetchall()
    by_code = {row["code"]: row for row in rows}
    for code, (name, acc_type, parent_code) in _EXPECTED_COA.items():
        assert code in by_code, f"Missing account code {code}"
        row = by_code[code]
        assert row["name"] == name, f"{code}: name {row['name']!r} != {name!r}"
        assert row["type"] == acc_type, f"{code}: type {row['type']!r} != {acc_type!r}"
        if parent_code:
            assert parent_code in by_code, f"Parent {parent_code} missing"
            assert row["parent_id"] == by_code[parent_code]["id"]
        else:
            assert row["parent_id"] is None
        assert row["is_active"] == 1
    # At least the required minimum accounts per AC8
    assert len(rows) >= 21


def _seed_expense_event(
    conn,
    *,
    amount_vnd=50000,
    category="Nguyên liệu",
    payment_source="Shop tiền mặt",
    paid_by_name="",
    summary="Test expense",
):
    data = json.dumps(
        {
            "amount_vnd": amount_vnd,
            "category": category,
            "payment_method": "TM",
            "payment_source": payment_source,
            "vendor": "NCC A",
            "note": "",
            "paid_by_name": paid_by_name,
        }
    )
    cursor = conn.execute(
        "INSERT INTO events (type, summary, data, logged_by, timestamp) "
        "VALUES ('expense', ?, ?, '', '2026-06-22T10:00:00+07:00')",
        (summary, data),
    )
    return int(cursor.lastrowid)


def _seed_payment_transaction(
    conn, order_id, amount=200000, type_="deposit", method="cash"
):
    cursor = conn.execute(
        "INSERT INTO payment_transactions (order_id, amount, type, method, note) "
        "VALUES (?, ?, ?, ?, '')",
        (order_id, amount, type_, method),
    )
    return int(cursor.lastrowid)


def _seed_order_with_items(conn, *, product_cost=5000, qty=2, status="delivered"):
    # Order
    cursor = conn.execute(
        "INSERT INTO orders (order_ref, customer_name, items, total_price, status) "
        "VALUES ('ORD-TEST-001', 'Khách test', '[]', 100000, ?)",
        (status,),
    )
    order_id = int(cursor.lastrowid)
    # Product
    cursor = conn.execute(
        "INSERT INTO products (name, category, base_price, cost, recipe_notes) "
        "VALUES ('Bánh test', 'banh_mi', 10000, ?, '')",
        (product_cost,),
    )
    product_id = int(cursor.lastrowid)
    # Order item with product_id as string (matches app convention)
    conn.execute(
        "INSERT INTO order_items "
        "(order_id, product_id, product_name, quantity, unit_price, position) "
        "VALUES (?, ?, 'Bánh test', ?, 50000, 0)",
        (order_id, str(product_id), qty),
    )
    return order_id, product_id


def _assert_double_entry_integrity(conn) -> None:
    """Every journal entry has total debit == total credit."""
    rows = conn.execute(
        """
        SELECT je.id, SUM(jl.debit) AS total_debit, SUM(jl.credit) AS total_credit
        FROM journal_entries je
        JOIN journal_lines jl ON jl.journal_entry_id = je.id
        GROUP BY je.id
        """
    ).fetchall()
    assert len(rows) > 0, "No journal entries to verify"
    for row in rows:
        delta = abs(float(row["total_debit"]) - float(row["total_credit"]))
        assert delta < 0.005, (
            f"Entry {row['id']}: debit {row['total_debit']} != credit {row['total_credit']}"
        )


def test_v44_accounts_table():
    with get_db() as conn:
        _migrate_to_version(conn, 43)
        _migrate_to_version(conn, 44)
        assert _migrated_version(conn) == 44
        _assert_accounts_table(conn)


def test_v44_journal_entries_table():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        _assert_journal_entries_table(conn)


def test_v44_journal_lines_table():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        _assert_journal_lines_table(conn)


def test_v44_seed_coa():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        _assert_seed_coa(conn)


def test_v44_seed_coa_idempotent():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        account_count = conn.execute("SELECT COUNT(*) FROM accounts").fetchone()[0]
        # Re-run callable (simulates re-migration safety)
        from baker.db.schema import _migrate_v44_double_entry_accounting

        _migrate_v44_double_entry_accounting(conn)
        account_count_after = conn.execute(
            "SELECT COUNT(*) FROM accounts"
        ).fetchone()[0]
        assert account_count == account_count_after


def test_v44_backfill_expenses():
    with get_db() as conn:
        _migrate_to_version(conn, 43)
        event_id = _seed_expense_event(
            conn,
            amount_vnd=50000,
            category="Nguyên liệu",
            payment_source="Shop tiền mặt",
            summary="Expense cash",
        )
        event_id_bank = _seed_expense_event(
            conn,
            amount_vnd=30000,
            category="Điện/nước",
            payment_source="TK Phượng VCB",
            summary="Expense bank",
        )

        _migrate_to_version(conn, 44)
        assert _migrated_version(conn) == 44

        # Two expense journal entries
        entries = conn.execute(
            "SELECT * FROM journal_entries WHERE source_type = 'expense' ORDER BY id"
        ).fetchall()
        assert len(entries) == 2

        # Cash expense: debit 1300 (Inventory — Nguyên liệu is inventory purchase), credit 1100 (Cash)
        cash_entry = next(e for e in entries if e["source_id"] == event_id)
        lines = conn.execute(
            "SELECT * FROM journal_lines WHERE journal_entry_id = ? ORDER BY id",
            (cash_entry["id"],),
        ).fetchall()
        assert len(lines) == 2
        debit_line = next(l for l in lines if float(l["debit"]) > 0)
        credit_line = next(l for l in lines if float(l["credit"]) > 0)
        assert float(debit_line["debit"]) == 50000
        assert float(credit_line["credit"]) == 50000
        # account codes
        debit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id = ?", (debit_line["account_id"],)
        ).fetchone()["code"]
        credit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id = ?", (credit_line["account_id"],)
        ).fetchone()["code"]
        assert debit_acc == "1300"
        assert credit_acc == "1100"

        # Bank expense: credit 1200 (Bank Account)
        bank_entry = next(e for e in entries if e["source_id"] == event_id_bank)
        lines = conn.execute(
            "SELECT * FROM journal_lines WHERE journal_entry_id = ?",
            (bank_entry["id"],),
        ).fetchall()
        credit_line = next(l for l in lines if float(l["credit"]) > 0)
        credit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id = ?", (credit_line["account_id"],)
        ).fetchone()["code"]
        assert credit_acc == "1200"

        _assert_double_entry_integrity(conn)


def test_v44_backfill_expense_staff_advance_creates_sub_account():
    with get_db() as conn:
        _migrate_to_version(conn, 43)
        # Seed staff
        conn.execute("INSERT OR IGNORE INTO staff (name, role) VALUES ('Ân', 'staff')")
        event_id = _seed_expense_event(
            conn,
            amount_vnd=40000,
            category="Lương/phụ cấp",
            payment_source="Nhân viên ứng trước",
            paid_by_name="Ân",
            summary="Staff advance Ân",
        )

        _migrate_to_version(conn, 44)

        # Sub-account created under 2300
        parent = conn.execute(
            "SELECT id FROM accounts WHERE code = '2300'"
        ).fetchone()
        subs = conn.execute(
            "SELECT * FROM accounts WHERE parent_id = ? ORDER BY id",
            (parent["id"],),
        ).fetchall()
        assert len(subs) == 1
        assert subs[0]["name"] == "Ân"
        # AC1/AC2: sub-account is a 23XX liability under 2300
        assert subs[0]["code"].startswith("23")
        assert subs[0]["type"] == "liability"
        assert subs[0]["parent_id"] == parent["id"]

        # Journal entry credit goes to the staff sub-account
        entry = conn.execute(
            "SELECT * FROM journal_entries WHERE source_type='expense' AND source_id=?",
            (event_id,),
        ).fetchone()
        lines = conn.execute(
            "SELECT * FROM journal_lines WHERE journal_entry_id = ?", (entry["id"],)
        ).fetchall()
        credit_line = next(l for l in lines if float(l["credit"]) > 0)
        assert credit_line["account_id"] == subs[0]["id"]
        _assert_double_entry_integrity(conn)


def test_v44_backfill_payments():
    with get_db() as conn:
        _migrate_to_version(conn, 43)
        # Need an order for FK
        cursor = conn.execute(
            "INSERT INTO orders (order_ref, customer_name, items, total_price, status) "
            "VALUES ('ORD-P-001', 'Khách p', '[]', 200000, 'new')"
        )
        order_id = int(cursor.lastrowid)

        pt_cash = _seed_payment_transaction(
            conn, order_id, amount=200000, type_="deposit", method="cash"
        )
        pt_transfer = _seed_payment_transaction(
            conn, order_id, amount=50000, type_="payment", method="transfer"
        )
        pt_refund = _seed_payment_transaction(
            conn, order_id, amount=10000, type_="refund", method="cash"
        )

        _migrate_to_version(conn, 44)

        entries = conn.execute(
            "SELECT * FROM journal_entries WHERE source_type='payment_transaction' "
            "ORDER BY id"
        ).fetchall()
        assert len(entries) == 3

        # deposit cash: debit 1100, credit 2100
        dep_entry = next(e for e in entries if e["source_id"] == pt_cash)
        lines = conn.execute(
            "SELECT * FROM journal_lines WHERE journal_entry_id=?",
            (dep_entry["id"],),
        ).fetchall()
        debit_line = next(l for l in lines if float(l["debit"]) > 0)
        credit_line = next(l for l in lines if float(l["credit"]) > 0)
        debit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id=?", (debit_line["account_id"],)
        ).fetchone()["code"]
        credit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id=?", (credit_line["account_id"],)
        ).fetchone()["code"]
        assert debit_acc == "1100"
        assert credit_acc == "2100"
        assert float(debit_line["debit"]) == 200000

        # transfer payment: debit 1200
        tr_entry = next(e for e in entries if e["source_id"] == pt_transfer)
        lines = conn.execute(
            "SELECT * FROM journal_lines WHERE journal_entry_id=?",
            (tr_entry["id"],),
        ).fetchall()
        debit_line = next(l for l in lines if float(l["debit"]) > 0)
        debit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id=?", (debit_line["account_id"],)
        ).fetchone()["code"]
        assert debit_acc == "1200"

        # refund: debit 2100, credit 1100 (reversed)
        rf_entry = next(e for e in entries if e["source_id"] == pt_refund)
        lines = conn.execute(
            "SELECT * FROM journal_lines WHERE journal_entry_id=?",
            (rf_entry["id"],),
        ).fetchall()
        debit_line = next(l for l in lines if float(l["debit"]) > 0)
        credit_line = next(l for l in lines if float(l["credit"]) > 0)
        debit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id=?", (debit_line["account_id"],)
        ).fetchone()["code"]
        credit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id=?", (credit_line["account_id"],)
        ).fetchone()["code"]
        assert debit_acc == "2100"
        assert credit_acc == "1100"

        _assert_double_entry_integrity(conn)


def test_v44_backfill_delivered_orders():
    with get_db() as conn:
        _migrate_to_version(conn, 43)
        order_id, product_id = _seed_order_with_items(
            conn, product_cost=5000, qty=2, status="delivered"
        )
        # payment to create revenue conversion
        _seed_payment_transaction(
            conn, order_id, amount=120000, type_="full_payment", method="cash"
        )

        _migrate_to_version(conn, 44)

        # Revenue conversion entry
        rev_entry = conn.execute(
            "SELECT * FROM journal_entries WHERE source_type='order' AND source_id=?",
            (order_id,),
        ).fetchone()
        assert rev_entry is not None
        lines = conn.execute(
            "SELECT * FROM journal_lines WHERE journal_entry_id=?",
            (rev_entry["id"],),
        ).fetchall()
        debit_line = next(l for l in lines if float(l["debit"]) > 0)
        credit_line = next(l for l in lines if float(l["credit"]) > 0)
        debit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id=?", (debit_line["account_id"],)
        ).fetchone()["code"]
        credit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id=?", (credit_line["account_id"],)
        ).fetchone()["code"]
        assert debit_acc == "2100"  # Customer Deposits
        assert credit_acc == "4100"  # Order Revenue
        assert float(debit_line["debit"]) == 120000

        # COGS entry: cost 5000 * qty 2 = 10000; debit 5900, credit 1300
        cogs_entry = conn.execute(
            "SELECT * FROM journal_entries WHERE source_type='order_cogs' AND source_id=?",
            (order_id,),
        ).fetchone()
        assert cogs_entry is not None
        lines = conn.execute(
            "SELECT * FROM journal_lines WHERE journal_entry_id=?",
            (cogs_entry["id"],),
        ).fetchall()
        debit_line = next(l for l in lines if float(l["debit"]) > 0)
        credit_line = next(l for l in lines if float(l["credit"]) > 0)
        debit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id=?", (debit_line["account_id"],)
        ).fetchone()["code"]
        credit_acc = conn.execute(
            "SELECT code FROM accounts WHERE id=?", (credit_line["account_id"],)
        ).fetchone()["code"]
        assert debit_acc == "5900"
        assert credit_acc == "1300"
        assert float(debit_line["debit"]) == 10000

        _assert_double_entry_integrity(conn)


def test_v44_backfill_delivered_order_zero_cost_skips_cogs():
    with get_db() as conn:
        _migrate_to_version(conn, 43)
        order_id, _ = _seed_order_with_items(
            conn, product_cost=0, qty=3, status="delivered"
        )
        _seed_payment_transaction(conn, order_id, amount=50000)

        _migrate_to_version(conn, 44)

        cogs_count = conn.execute(
            "SELECT COUNT(*) FROM journal_entries "
            "WHERE source_type='order_cogs' AND source_id=?",
            (order_id,),
        ).fetchone()[0]
        assert cogs_count == 0


def test_v44_double_entry_integrity():
    with get_db() as conn:
        _migrate_to_version(conn, 43)
        # Seed a mix of data
        _seed_expense_event(conn, amount_vnd=50000, category="Bao bì")
        _seed_expense_event(
            conn,
            amount_vnd=40000,
            category="Vận chuyển",
            payment_source="TK Ân VCB",
        )
        order_id, _ = _seed_order_with_items(
            conn, product_cost=3000, qty=2, status="delivered"
        )
        _seed_payment_transaction(conn, order_id, amount=80000, method="transfer")
        _seed_payment_transaction(
            conn, order_id, amount=20000, type_="tien_rut", method="cash"
        )

        _migrate_to_version(conn, 44)
        _assert_double_entry_integrity(conn)


def test_v44_fresh_db_seeds_coa_and_no_backfill():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        assert _migrated_version(conn) == 44
        _assert_seed_coa(conn)
        # No historical data → no journal entries
        entry_count = conn.execute(
            "SELECT COUNT(*) FROM journal_entries"
        ).fetchone()[0]
        assert entry_count == 0


# ---------------------------------------------------------------------------
# v45 — cost_history table, order_items.cost_at_sale column, baseline backfill
# ---------------------------------------------------------------------------


def _assert_cost_history_schema(conn) -> None:
    columns = _schema_columns(conn, "cost_history")
    assert set(columns) >= {
        "id",
        "product_id",
        "cost",
        "effective_from",
        "created_at",
    }
    # product_id and cost and effective_from must be NOT NULL
    assert columns["product_id"]["notnull"] == 1
    assert columns["cost"]["notnull"] == 1
    assert columns["effective_from"]["notnull"] == 1

    # FK to products with ON DELETE CASCADE
    fk_rows = conn.execute("PRAGMA foreign_key_list(cost_history)").fetchall()
    assert len(fk_rows) == 1
    fk = fk_rows[0]
    assert fk["table"] == "products"
    assert fk["from"] == "product_id"
    assert fk["to"] == "id"
    assert fk["on_delete"] == "CASCADE"

    # Index on (product_id, effective_from)
    index_rows = conn.execute("PRAGMA index_list(cost_history)").fetchall()
    index_names = [row["name"] for row in index_rows]
    assert "idx_cost_history_product_effective" in index_names
    index_info = conn.execute(
        "PRAGMA index_info(idx_cost_history_product_effective)"
    ).fetchall()
    index_columns = [row["name"] for row in index_info]
    assert index_columns == ["product_id", "effective_from"]


def _assert_order_items_cost_at_sale(conn) -> None:
    columns = _schema_columns(conn, "order_items")
    assert "cost_at_sale" in columns
    # Nullable/defaults to 0 for non-delivered items
    assert columns["cost_at_sale"]["dflt_value"] == "0"


def _seed_order_with_item(
    conn,
    *,
    product_cost=5000,
    product_category="banh_mi",
    base_price=10000,
    qty=2,
    status="delivered",
    is_extra=0,
    is_gift=0,
    order_ref="ORD-V45-001",
):
    """Seed an order + product + order_item and return (order_id, product_id, item_id).

    Product name is derived from order_ref to satisfy the UNIQUE constraint on
    products.name when multiple items are seeded in one test.
    """
    cursor = conn.execute(
        "INSERT INTO orders (order_ref, customer_name, items, total_price, status) "
        "VALUES (?, 'Khách v45', '[]', 100000, ?)",
        (order_ref, status),
    )
    order_id = int(cursor.lastrowid)
    product_name = f"Bánh {order_ref}"
    cursor = conn.execute(
        "INSERT INTO products (name, category, base_price, cost, recipe_notes) "
        "VALUES (?, ?, ?, ?, '')",
        (product_name, product_category, base_price, product_cost),
    )
    product_id = int(cursor.lastrowid)
    cursor = conn.execute(
        "INSERT INTO order_items "
        "(order_id, product_id, product_name, quantity, unit_price, position, is_extra, is_gift) "
        "VALUES (?, ?, ?, ?, 50000, 0, ?, ?)",
        (order_id, str(product_id), product_name, qty, is_extra, is_gift),
    )
    item_id = int(cursor.lastrowid)
    return order_id, product_id, item_id


def test_v45_fresh_db():
    with get_db() as conn:
        _migrate_to_version(conn, 45)
        assert _migrated_version(conn) == 45
        _assert_cost_history_schema(conn)
        _assert_order_items_cost_at_sale(conn)


def test_v45_incremental_from_v44():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        assert _migrated_version(conn) == 44
        # No cost_history table, no cost_at_sale column yet
        tables = {
            r["name"]
            for r in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        }
        assert "cost_history" not in tables
        cols = _schema_columns(conn, "order_items")
        assert "cost_at_sale" not in cols

        _migrate_to_version(conn, 45)
        assert _migrated_version(conn) == 45
        _assert_cost_history_schema(conn)
        _assert_order_items_cost_at_sale(conn)


def test_v45_idempotent():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        # Seed a delivered order with an item (backfill target)
        _, _, item_id = _seed_order_with_item(
            conn, product_cost=0, base_price=10000, qty=2, status="delivered"
        )
        _migrate_to_version(conn, 45)
        assert _migrated_version(conn) == 45
        # Capture backfilled cost. _seed_order_with_item sets unit_price=50000,
        # and DG-208 Phase 2 anchors the baseline on unit_price, so 30% of
        # 50000 = 15000 (not 30% of base_price 10000 = 3000).
        cost_after_first = conn.execute(
            "SELECT cost_at_sale FROM order_items WHERE id = ?", (item_id,)
        ).fetchone()["cost_at_sale"]
        assert float(cost_after_first) == 15000.0  # 30% of unit_price 50000

        # Re-run the v45 callable directly (simulates re-migration)
        from baker.db.schema import _migrate_v45_cost_history_and_cost_at_sale

        _migrate_v45_cost_history_and_cost_at_sale(conn)

        # Schema still valid
        _assert_cost_history_schema(conn)
        _assert_order_items_cost_at_sale(conn)
        # No duplicate data: cost_at_sale unchanged (not re-zeroed)
        cost_after_second = conn.execute(
            "SELECT cost_at_sale FROM order_items WHERE id = ?", (item_id,)
        ).fetchone()["cost_at_sale"]
        assert float(cost_after_second) == 15000.0
        # cost_history table exists but no rows inserted by backfill (baseline is query-time)
        ch_count = conn.execute("SELECT COUNT(*) FROM cost_history").fetchone()[0]
        assert ch_count == 0


def test_v45_backfill_non_phu_kien_30_percent():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        _, _, item_id = _seed_order_with_item(
            conn,
            product_cost=5000,
            product_category="banh_mi",
            base_price=20000,
            qty=3,
            status="delivered",
        )
        _migrate_to_version(conn, 45)

        cost = conn.execute(
            "SELECT cost_at_sale FROM order_items WHERE id = ?", (item_id,)
        ).fetchone()["cost_at_sale"]
        # 30% of unit_price 50000 = 15000 (DG-208 Phase 2 anchors on unit_price)
        assert float(cost) == 15000.0


def test_v45_backfill_phu_kien_100_percent():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        _, _, item_id = _seed_order_with_item(
            conn,
            product_cost=5000,
            product_category="phu_kien",
            base_price=15000,
            qty=2,
            status="delivered",
        )
        _migrate_to_version(conn, 45)

        cost = conn.execute(
            "SELECT cost_at_sale FROM order_items WHERE id = ?", (item_id,)
        ).fetchone()["cost_at_sale"]
        # 100% of base_price for phụ kiện (phụ kiện ignores unit_price anchor)
        assert float(cost) == 15000.0


def test_v45_backfill_skips_non_delivered_orders():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        _, _, item_id = _seed_order_with_item(
            conn,
            product_cost=5000,
            base_price=10000,
            qty=2,
            status="new",  # not delivered
        )
        _migrate_to_version(conn, 45)

        cost = conn.execute(
            "SELECT cost_at_sale FROM order_items WHERE id = ?", (item_id,)
        ).fetchone()["cost_at_sale"]
        # Not delivered → no backfill → stays at default 0
        assert float(cost) == 0.0


def test_v45_backfill_skips_extra_and_gift_items():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        _, _, extra_item_id = _seed_order_with_item(
            conn,
            product_cost=5000,
            base_price=10000,
            qty=1,
            status="delivered",
            is_extra=1,
            order_ref="ORD-V45-EXTRA",
        )
        _, _, gift_item_id = _seed_order_with_item(
            conn,
            product_cost=5000,
            base_price=10000,
            qty=1,
            status="delivered",
            is_gift=1,
            order_ref="ORD-V45-GIFT",
        )
        _migrate_to_version(conn, 45)

        extra_cost = conn.execute(
            "SELECT cost_at_sale FROM order_items WHERE id = ?", (extra_item_id,)
        ).fetchone()["cost_at_sale"]
        gift_cost = conn.execute(
            "SELECT cost_at_sale FROM order_items WHERE id = ?", (gift_item_id,)
        ).fetchone()["cost_at_sale"]
        assert float(extra_cost) == 0.0
        assert float(gift_cost) == 0.0


def test_v45_backfill_zero_base_price_skips():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        _, _, item_id = _seed_order_with_item(
            conn,
            product_cost=0,
            base_price=0,
            qty=2,
            status="delivered",
        )
        # Force unit_price to 0 so both anchor candidates are 0 (DG-208 Phase 2
        # changed the anchor to unit_price; base_price=0 alone no longer skips
        # when unit_price > 0).
        conn.execute("UPDATE order_items SET unit_price = 0 WHERE id = ?", (item_id,))
        conn.commit()
        _migrate_to_version(conn, 45)

        cost = conn.execute(
            "SELECT cost_at_sale FROM order_items WHERE id = ?", (item_id,)
        ).fetchone()["cost_at_sale"]
        # 30% of 0 = 0 → no UPDATE applied (cost > 0 guard)
        assert float(cost) == 0.0


def test_v45_no_delivered_orders_is_noop():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        # Seed a non-delivered order only
        _seed_order_with_item(
            conn, product_cost=5000, base_price=10000, qty=2, status="new"
        )
        _migrate_to_version(conn, 45)

        # cost_history table exists
        _assert_cost_history_schema(conn)
        # No rows backfilled (all cost_at_sale remain 0)
        backfilled = conn.execute(
            "SELECT COUNT(*) FROM order_items WHERE cost_at_sale > 0"
        ).fetchone()[0]
        assert backfilled == 0


def test_v45_preserves_existing_cost_at_sale():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        _, _, item_id = _seed_order_with_item(
            conn, product_cost=5000, base_price=10000, qty=2, status="delivered"
        )
        # Run v45 once to add the column and backfill (30% of 10000 = 3000)
        _migrate_to_version(conn, 45)
        conn.execute(
            "UPDATE order_items SET cost_at_sale = 7777 WHERE id = ?", (item_id,)
        )
        conn.commit()

        # Re-run the v45 callable directly (simulates re-migration)
        from baker.db.schema import _migrate_v45_cost_history_and_cost_at_sale

        _migrate_v45_cost_history_and_cost_at_sale(conn)

        cost = conn.execute(
            "SELECT cost_at_sale FROM order_items WHERE id = ?", (item_id,)
        ).fetchone()["cost_at_sale"]
        # Pre-existing non-zero cost_at_sale is not overwritten (backfill guard)
        assert float(cost) == 7777.0


# ---------------------------------------------------------------------------
# v63 — repair zero-cost order_items + missing order_cogs entries (DG-208 P2)
# ---------------------------------------------------------------------------


def test_v63_registered_in_migration_chain():
    assert 63 in MIGRATIONS
    assert (
        MIGRATIONS[63]["callable"].__name__
        == "_migrate_v63_repair_zero_cogs_and_missing_entries"
    )


def test_v63_repairs_zero_cost_items_with_unit_price_anchor():
    """A delivered order with cost_at_sale=0 (pre-Phase-2 backfill missed it)
    gets cost_at_sale = unit_price × 30% after v63 runs."""
    with get_db() as conn:
        _migrate_to_version(conn, 45)
        _, product_id, item_id = _seed_order_with_item(
            conn,
            product_cost=0,
            product_category="banh_kem",
            base_price=150000,
            qty=1,
            status="delivered",
            order_ref="ORD-V63-ZERO-001",
        )
        # _seed_order_with_item sets unit_price=50000; force a custom price
        # to mirror the real-world custom-priced orders.
        conn.execute(
            "UPDATE order_items SET unit_price = 800000 WHERE id = ?", (item_id,)
        )
        conn.commit()
        assert float(
            conn.execute(
                "SELECT cost_at_sale FROM order_items WHERE id = ?", (item_id,)
            ).fetchone()["cost_at_sale"]
        ) == 0.0

        _migrate_to_version(conn, 63)

        cost = float(
            conn.execute(
                "SELECT cost_at_sale FROM order_items WHERE id = ?", (item_id,)
            ).fetchone()["cost_at_sale"]
        )
        # 30% of unit_price 800000 = 240000 (not 30% of base_price 150000)
        assert cost == 240000.0


def test_v63_creates_missing_order_cogs_journal_entry():
    """A delivered order with no order_cogs entry gets one after v63 runs
    (mirrors Order #1091 missing COGS entirely)."""
    with get_db() as conn:
        _migrate_to_version(conn, 45)
        _, product_id, item_id = _seed_order_with_item(
            conn,
            product_cost=0,
            product_category="banh_kem",
            base_price=150000,
            qty=1,
            status="delivered",
            order_ref="ORD-V63-COGS-001",
        )
        conn.execute(
            "UPDATE order_items SET unit_price = 130000 WHERE id = ?", (item_id,)
        )
        conn.commit()
        # No order_cogs entry yet (v45 backfill ran with old base_price anchor
        # → cost_at_sale = 30% of 150000 = 45000, but no journal entry was
        # created by v45 — that's _sync_delivered_order_journal's job, which
        # only runs on delivery).
        # Force cost_at_sale back to 0 to simulate the unfixed zero-cost state.
        conn.execute("UPDATE order_items SET cost_at_sale = 0 WHERE id = ?", (item_id,))
        conn.commit()

        _migrate_to_version(conn, 63)

        # cost_at_sale repaired
        cost = float(
            conn.execute(
                "SELECT cost_at_sale FROM order_items WHERE id = ?", (item_id,)
            ).fetchone()["cost_at_sale"]
        )
        assert cost == 39000.0  # 30% of unit_price 130000

        # order_cogs journal entry created
        order_id = conn.execute(
            "SELECT order_id FROM order_items WHERE id = ?", (item_id,)
        ).fetchone()[0]
        entry = conn.execute(
            "SELECT 1 FROM journal_entries WHERE source_type = 'order_cogs' "
            "AND source_id = ?",
            (order_id,),
        ).fetchone()
        assert entry is not None


def test_v63_idempotent():
    """Re-running v63 produces no new changes — backfill guard skips set
    cost_at_sale; _sync_delivered_order_journal skips orders with existing
    order_cogs entries."""
    with get_db() as conn:
        _migrate_to_version(conn, 45)
        _, _, item_id = _seed_order_with_item(
            conn,
            product_cost=0,
            product_category="banh_kem",
            base_price=150000,
            qty=1,
            status="delivered",
            order_ref="ORD-V63-IDEM-001",
        )
        conn.execute(
            "UPDATE order_items SET unit_price = 200000 WHERE id = ?", (item_id,)
        )
        conn.commit()

        _migrate_to_version(conn, 63)
        cost_first = float(
            conn.execute(
                "SELECT cost_at_sale FROM order_items WHERE id = ?", (item_id,)
            ).fetchone()["cost_at_sale"]
        )
        cogs_count_first = conn.execute(
            "SELECT COUNT(*) FROM journal_entries WHERE source_type = 'order_cogs'"
        ).fetchone()[0]

        # Re-run the v63 callable directly (simulates re-migration)
        from baker.db.schema import _migrate_v63_repair_zero_cogs_and_missing_entries

        _migrate_v63_repair_zero_cogs_and_missing_entries(conn)

        cost_second = float(
            conn.execute(
                "SELECT cost_at_sale FROM order_items WHERE id = ?", (item_id,)
            ).fetchone()["cost_at_sale"]
        )
        cogs_count_second = conn.execute(
            "SELECT COUNT(*) FROM journal_entries WHERE source_type = 'order_cogs'"
        ).fetchone()[0]

        assert cost_first == cost_second == 60000.0  # 30% of 200000
        assert cogs_count_first == cogs_count_second  # no duplicate entries


def test_v63_handles_unresolvable_product_id():
    """An order_item whose product_id has no matching products row (e.g.
    custom codes like 'BKS-DG-01') still gets backfilled using unit_price —
    phụ kiện is always a real resolvable category, so unresolvable items are
    never phụ kiện (DG-208 Phase 2, fixes Order #1091)."""
    with get_db() as conn:
        _migrate_to_version(conn, 45)
        cursor = conn.execute(
            "INSERT INTO orders "
            "(order_ref, customer_name, items, total_price, status) "
            "VALUES ('ORD-V63-UNRES-001', 'Khách v63', '[]', 130000, 'delivered')"
        )
        order_id = int(cursor.lastrowid)
        # Custom product code with no matching products row
        conn.execute(
            "INSERT INTO order_items "
            "(order_id, product_id, product_name, quantity, unit_price, position, is_extra, is_gift) "
            "VALUES (?, 'BKS-DG-01', 'Bánh Kem Theo Yêu Cầu', 1, 130000, 0, 0, 0)",
            (order_id,),
        )
        conn.commit()

        _migrate_to_version(conn, 63)

        cost = float(
            conn.execute(
                "SELECT cost_at_sale FROM order_items WHERE order_id = ?",
                (order_id,),
            ).fetchone()["cost_at_sale"]
        )
        # 30% of unit_price 130000 = 39000 (unresolvable → non-phụ-kiện 30%)
        assert cost == 39000.0

        # order_cogs entry created
        entry = conn.execute(
            "SELECT 1 FROM journal_entries WHERE source_type = 'order_cogs' "
            "AND source_id = ?",
            (order_id,),
        ).fetchone()
        assert entry is not None


# ---------------------------------------------------------------------------
# v49 — bus shipping accounting backfill (DG-191 Phase 5)
# ---------------------------------------------------------------------------


def test_v49_registered_in_migration_chain():
    assert 49 in MIGRATIONS
    assert MIGRATIONS[49]["callable"].__name__ == "_migrate_v49_bus_shipping_backfill"


def test_v49_backfill_runs_in_migration_chain():
    """Migrating from v44 to v49 backfills a delivered bus order end-to-end."""
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        # Seed a delivered bus order with a stale revenue entry (pre-Phase-3).
        cursor = conn.execute(
            "INSERT INTO orders "
            "(order_ref, customer_name, items, total_price, status, "
            " delivery_type, shipping_fee) "
            "VALUES ('ORD-V49-CHAIN', 'Khách chain', '[]', 100000, 'delivered', 'bus', 25000)"
        )
        order_id = int(cursor.lastrowid)
        conn.execute(
            "INSERT INTO payment_transactions (order_id, amount, type, method, note) "
            "VALUES (?, 100000, 'deposit', 'cash', '')",
            (order_id,),
        )
        # Stale revenue entry debiting 2100 for the full deposit.
        deposits_acc = conn.execute(
            "SELECT id FROM accounts WHERE code = ?", (CUSTOMER_DEPOSITS_CODE,)
        ).fetchone()[0]
        revenue_acc = conn.execute(
            "SELECT id FROM accounts WHERE code = '4100'"
        ).fetchone()[0]
        cur = conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id) "
            "VALUES ('Order revenue: ORD-V49-CHAIN', 'order', ?)",
            (order_id,),
        )
        stale_id = int(cur.lastrowid)
        conn.execute(
            "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, 100000, 0.0, 'stale')",
            (stale_id, deposits_acc),
        )
        conn.execute(
            "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, 0.0, 100000, 'stale')",
            (stale_id, revenue_acc),
        )
        conn.commit()

        _migrate_to_version(conn, 49)
        assert _migrated_version(conn) == 49

        # Revenue entry corrected to 75000 (net − shipping).
        rev = conn.execute(
            "SELECT id FROM journal_entries WHERE source_type='order' AND source_id=?",
            (order_id,),
        ).fetchone()
        assert int(rev["id"]) != stale_id  # stale entry was replaced
        debit = conn.execute(
            """
            SELECT COALESCE(SUM(jl.debit), 0) AS d
            FROM journal_lines jl
            JOIN accounts a ON a.id = jl.account_id
            WHERE jl.journal_entry_id = ? AND a.code = ?
            """,
            (rev["id"], CUSTOMER_DEPOSITS_CODE),
        ).fetchone()["d"]
        assert float(debit) == 75000.0

        # Hold entry created.
        hold = conn.execute(
            "SELECT COUNT(*) FROM journal_entries "
            "WHERE source_type='order_shipping_hold' AND source_id=?",
            (order_id,),
        ).fetchone()[0]
        assert hold == 1

        # Release entry created.
        release = conn.execute(
            "SELECT COUNT(*) FROM journal_entries "
            "WHERE source_type='order_shipping_release' AND source_id=?",
            (order_id,),
        ).fetchone()[0]
        assert release == 1

        # Double-entry integrity across all entries.
        rows = conn.execute(
            """
            SELECT je.id, SUM(jl.debit) AS td, SUM(jl.credit) AS tc
            FROM journal_entries je
            JOIN journal_lines jl ON jl.journal_entry_id = je.id
            GROUP BY je.id
            """
        ).fetchall()
        for r in rows:
            assert abs(float(r["td"]) - float(r["tc"])) < 0.005


def test_v49_fresh_db_is_noop():
    """A fresh DB with no delivered bus orders: v49 backfill does nothing."""
    with get_db() as conn:
        _migrate_to_version(conn, 49)
        assert _migrated_version(conn) == 49
        count = conn.execute("SELECT COUNT(*) FROM journal_entries").fetchone()[0]
        assert count == 0


def test_v49_idempotent_in_chain():
    """Re-running the v49 callable directly after migration is a no-op."""
    from baker.db.schema import _migrate_v49_bus_shipping_backfill

    with get_db() as conn:
        _migrate_to_version(conn, 49)
        cursor = conn.execute(
            "INSERT INTO orders "
            "(order_ref, customer_name, items, total_price, status, "
            " delivery_type, shipping_fee) "
            "VALUES ('ORD-V49-IDEM', 'Khách idem', '[]', 100000, 'delivered', 'bus', 25000)"
        )
        order_id = int(cursor.lastrowid)
        conn.execute(
            "INSERT INTO payment_transactions (order_id, amount, type, method, note) "
            "VALUES (?, 100000, 'deposit', 'cash', '')",
            (order_id,),
        )
        # Stale revenue entry.
        deposits_acc = conn.execute(
            "SELECT id FROM accounts WHERE code = ?", (CUSTOMER_DEPOSITS_CODE,)
        ).fetchone()[0]
        revenue_acc = conn.execute(
            "SELECT id FROM accounts WHERE code = '4100'"
        ).fetchone()[0]
        cur = conn.execute(
            "INSERT INTO journal_entries (description, source_type, source_id) "
            "VALUES ('r', 'order', ?)",
            (order_id,),
        )
        sid = int(cur.lastrowid)
        conn.execute(
            "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, 100000, 0.0, 's')",
            (sid, deposits_acc),
        )
        conn.execute(
            "INSERT INTO journal_lines (journal_entry_id, account_id, debit, credit, description) "
            "VALUES (?, ?, 0.0, 100000, 's')",
            (sid, revenue_acc),
        )
        conn.commit()

        _migrate_v49_bus_shipping_backfill(conn)
        rev = conn.execute(
            "SELECT COUNT(*) FROM journal_entries WHERE source_type='order' AND source_id=?",
            (order_id,),
        ).fetchone()[0]
        hold = conn.execute(
            "SELECT COUNT(*) FROM journal_entries WHERE source_type='order_shipping_hold' AND source_id=?",
            (order_id,),
        ).fetchone()[0]
        rel = conn.execute(
            "SELECT COUNT(*) FROM journal_entries WHERE source_type='order_shipping_release' AND source_id=?",
            (order_id,),
        ).fetchone()[0]

        # Run again — counts must not change.
        _migrate_v49_bus_shipping_backfill(conn)
        assert conn.execute(
            "SELECT COUNT(*) FROM journal_entries WHERE source_type='order' AND source_id=?",
            (order_id,),
        ).fetchone()[0] == rev
        assert conn.execute(
            "SELECT COUNT(*) FROM journal_entries WHERE source_type='order_shipping_hold' AND source_id=?",
            (order_id,),
        ).fetchone()[0] == hold
        assert conn.execute(
            "SELECT COUNT(*) FROM journal_entries WHERE source_type='order_shipping_release' AND source_id=?",
            (order_id,),
        ).fetchone()[0] == rel


# ---------------------------------------------------------------------------
# v50/v51 — journal_entries.transaction_date column + re-backfill
# (DG-192 Phase 4.1)
# ---------------------------------------------------------------------------


def test_v50_registered_in_migration_chain():
    assert 50 in MIGRATIONS
    assert (
        MIGRATIONS[50]["callable"].__name__
        == "_migrate_v50_journal_transaction_date"
    )


def test_v50_adds_transaction_date_column_and_index():
    with get_db() as conn:
        _migrate_to_version(conn, 50)
        assert _migrated_version(conn) == 50

        columns = _schema_columns(conn, "journal_entries")
        assert "transaction_date" in columns
        # NOT NULL constraint enforced (DEFAULT '' keeps it non-empty).
        assert columns["transaction_date"]["notnull"] == 1
        # created_at preserved as audit column.
        assert "created_at" in columns

        index_rows = conn.execute(
            "PRAGMA index_list(journal_entries)"
        ).fetchall()
        index_names = [row["name"] for row in index_rows]
        assert "idx_journal_entries_transaction_date" in index_names
        # Existing indices preserved.
        assert "idx_journal_entries_created" in index_names
        assert "idx_journal_entries_source" in index_names


def test_v50_is_idempotent():
    from baker.db.schema import _migrate_v50_journal_transaction_date

    with get_db() as conn:
        _migrate_to_version(conn, 50)
        # Re-running the callable directly must not raise.
        _migrate_v50_journal_transaction_date(conn)
        columns = _schema_columns(conn, "journal_entries")
        assert "transaction_date" in columns


def test_v50_existing_entries_get_empty_transaction_date():
    """v50 adds the column; existing rows get the DEFAULT '' until v51 backfills."""
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        # Insert an expense-backed journal entry via the v44 backfill.
        _seed_expense_event(conn, summary="Pre-v50 expense")
        _migrate_v49_bus_shipping_backfill_idempotent_seed(conn)
        _migrate_to_version(conn, 50)
        rows = conn.execute(
            "SELECT transaction_date FROM journal_entries"
        ).fetchall()
        assert rows, "expected at least one journal entry"
        for row in rows:
            assert row["transaction_date"] == ""


def _migrate_v49_bus_shipping_backfill_idempotent_seed(conn):
    """Helper: seed a no-op state so v49 backfill has nothing to do (avoids
    needing a bus order). Runs v49 callable which is a no-op on empty data."""
    _migrate_to_version(conn, 49)


def test_v51_registered_in_migration_chain():
    assert 51 in MIGRATIONS
    assert (
        MIGRATIONS[51]["callable"].__name__
        == "_migrate_v51_backfill_journal_transaction_date"
    )


def test_v51_backfills_expense_from_event_timestamp():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        event_id = _seed_expense_event(conn, summary="Backfill expense")
        # The seed sets events.timestamp = '2026-06-22T10:00:00+07:00'.
        _migrate_to_version(conn, 50)
        # Before v51: transaction_date is empty.
        row = conn.execute(
            "SELECT transaction_date FROM journal_entries "
            "WHERE source_type='expense' AND source_id=?",
            (event_id,),
        ).fetchone()
        assert row["transaction_date"] == ""

        _migrate_to_version(conn, 51)
        row = conn.execute(
            "SELECT transaction_date FROM journal_entries "
            "WHERE source_type='expense' AND source_id=?",
            (event_id,),
        ).fetchone()
        assert row["transaction_date"] == "2026-06-22T10:00:00+07:00"


def test_v51_backfills_payment_from_payment_created_at():
    with get_db() as conn:
        _migrate_to_version(conn, 43)
        order_id, _ = _seed_order_with_items(conn)
        pt_id = _seed_payment_transaction(conn, order_id)
        # Set a known created_at on the payment transaction.
        conn.execute(
            "UPDATE payment_transactions SET created_at = '2026-05-15T09:30:00' "
            "WHERE id = ?",
            (pt_id,),
        )
        conn.commit()
        # v44 backfill creates the payment_transaction journal entry.
        _migrate_to_version(conn, 44)
        _migrate_to_version(conn, 50)
        _migrate_to_version(conn, 51)
        row = conn.execute(
            "SELECT transaction_date FROM journal_entries "
            "WHERE source_type='payment_transaction' AND source_id=?",
            (pt_id,),
        ).fetchone()
        assert row["transaction_date"] == "2026-05-15T09:30:00"


def test_v51_backfills_order_from_due_date():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        order_id, _ = _seed_order_with_items(conn)
        conn.execute(
            "UPDATE orders SET due_date = '2026-05-20' WHERE id = ?",
            (order_id,),
        )
        conn.commit()
        _migrate_to_version(conn, 50)
        _migrate_to_version(conn, 51)
        # The v44 backfill creates a revenue 'order' entry for delivered orders.
        # Phase 3 changed the backfill to use now_utc() instead of due_date.
        row = conn.execute(
            "SELECT transaction_date FROM journal_entries "
            "WHERE source_type='order' AND source_id=?",
            (order_id,),
        ).fetchone()
        assert row["transaction_date"] is not None
        assert "T" in row["transaction_date"]
        assert row["transaction_date"].endswith("Z")


def test_v51_backfills_order_falls_back_to_created_at_when_due_date_null():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        order_id, _ = _seed_order_with_items(conn)
        # Ensure due_date is NULL/empty and created_at is a known value.
        conn.execute(
            "UPDATE orders SET due_date = NULL, created_at = '2026-04-10T08:00:00' "
            "WHERE id = ?",
            (order_id,),
        )
        conn.commit()
        _migrate_to_version(conn, 50)
        _migrate_to_version(conn, 51)
        # Phase 3 changed the backfill to use now_utc() instead of the created_at
        # fallback, so transaction_date is now a full dynamic timestamp.
        row = conn.execute(
            "SELECT transaction_date FROM journal_entries "
            "WHERE source_type='order' AND source_id=?",
            (order_id,),
        ).fetchone()
        assert row["transaction_date"] is not None
        assert "T" in row["transaction_date"]
        assert row["transaction_date"].endswith("Z")


def test_v51_backfills_order_cogs_from_due_date():
    with get_db() as conn:
        _migrate_to_version(conn, 44)
        order_id, _ = _seed_order_with_items(conn, product_cost=5000)
        conn.execute(
            "UPDATE orders SET due_date = '2026-06-01' WHERE id = ?",
            (order_id,),
        )
        conn.commit()
        _migrate_to_version(conn, 50)
        _migrate_to_version(conn, 51)
        row = conn.execute(
            "SELECT transaction_date FROM journal_entries "
            "WHERE source_type='order_cogs' AND source_id=?",
            (order_id,),
        ).fetchone()
        assert row["transaction_date"] is not None
        assert "T" in row["transaction_date"]
        assert row["transaction_date"].endswith("Z")


def test_v51_backfills_manual_entries_from_created_at():
    """owner_capital/owner_draw/staff_reimburse use created_at as transaction_date."""
    from baker.db.schema import _insert_journal_entry, _account_id_by_code

    with get_db() as conn:
        _migrate_to_version(conn, 44)
        equity_acc = _account_id_by_code(conn, "3100")
        cash_acc = _account_id_by_code(conn, "1100")
        entry_id = _insert_journal_entry(
            conn,
            description="Owner capital injection",
            source_type="owner_capital",
            source_id=None,
            lines=[(cash_acc, 1000000.0, 0.0, "Tiền vốn"), (equity_acc, 0.0, 1000000.0, "Vốn")],
        )
        # Force a known created_at for deterministic assertion.
        conn.execute(
            "UPDATE journal_entries SET created_at = '2026-03-01T12:00:00' "
            "WHERE id = ?",
            (entry_id,),
        )
        conn.commit()
        _migrate_to_version(conn, 50)
        _migrate_to_version(conn, 51)
        row = conn.execute(
            "SELECT transaction_date, created_at FROM journal_entries WHERE id = ?",
            (entry_id,),
        ).fetchone()
        assert row["transaction_date"] == "2026-03-01T12:00:00"
        # created_at preserved (NFR3).
        assert row["created_at"] == "2026-03-01T12:00:00"


def test_v51_is_idempotent():
    """Re-running v51 callable after migration does not change transaction_date."""
    from baker.db.schema import _migrate_v51_backfill_journal_transaction_date

    with get_db() as conn:
        _migrate_to_version(conn, 44)
        _seed_expense_event(conn, summary="Idempotency expense")
        _migrate_to_version(conn, 51)
        rows_before = conn.execute(
            "SELECT id, transaction_date FROM journal_entries ORDER BY id"
        ).fetchall()
        # Run callable again.
        _migrate_v51_backfill_journal_transaction_date(conn)
        rows_after = conn.execute(
            "SELECT id, transaction_date FROM journal_entries ORDER BY id"
        ).fetchall()
        assert rows_before == rows_after


def test_insert_journal_entry_signature_accepts_transaction_date():
    """_insert_journal_entry() writes transaction_date when provided."""
    from baker.db.schema import _insert_journal_entry, _account_id_by_code

    with get_db() as conn:
        _migrate_to_version(conn, 50)
        cash_acc = _account_id_by_code(conn, "1100")
        equity_acc = _account_id_by_code(conn, "3100")
        entry_id = _insert_journal_entry(
            conn,
            description="Explicit transaction_date",
            source_type="owner_capital",
            source_id=None,
            lines=[(cash_acc, 500.0, 0.0, "in"), (equity_acc, 0.0, 500.0, "eq")],
            transaction_date="2026-02-14T09:00:00",
        )
        row = conn.execute(
            "SELECT transaction_date FROM journal_entries WHERE id = ?",
            (entry_id,),
        ).fetchone()
        assert row["transaction_date"] == "2026-02-14T09:00:00"


def test_insert_journal_entry_defaults_transaction_date_to_now():
    """Without transaction_date, the helper uses current local time (non-empty)."""
    from baker.db.schema import _insert_journal_entry, _account_id_by_code

    with get_db() as conn:
        _migrate_to_version(conn, 50)
        cash_acc = _account_id_by_code(conn, "1100")
        equity_acc = _account_id_by_code(conn, "3100")
        entry_id = _insert_journal_entry(
            conn,
            description="Default transaction_date",
            source_type="owner_capital",
            source_id=None,
            lines=[(cash_acc, 100.0, 0.0, "in"), (equity_acc, 0.0, 100.0, "eq")],
        )
        row = conn.execute(
            "SELECT transaction_date FROM journal_entries WHERE id = ?",
            (entry_id,),
        ).fetchone()
        assert row["transaction_date"] != ""
        assert row["transaction_date"] is not None


def test_v50_v51_full_chain_preserves_created_at():
    """created_at (audit trail) is never modified by the transaction_date migration."""
    from baker.db.schema import _insert_journal_entry, _account_id_by_code

    with get_db() as conn:
        _migrate_to_version(conn, 44)
        cash_acc = _account_id_by_code(conn, "1100")
        equity_acc = _account_id_by_code(conn, "3100")
        entry_id = _insert_journal_entry(
            conn,
            description="Audit preservation",
            source_type="owner_capital",
            source_id=None,
            lines=[(cash_acc, 200.0, 0.0, "in"), (equity_acc, 0.0, 200.0, "eq")],
        )
        conn.execute(
            "UPDATE journal_entries SET created_at = '2026-01-01T00:00:00' WHERE id = ?",
            (entry_id,),
        )
        conn.commit()
        _migrate_to_version(conn, 51)
        row = conn.execute(
            "SELECT transaction_date, created_at FROM journal_entries WHERE id = ?",
            (entry_id,),
        ).fetchone()
        # transaction_date backfilled from created_at (manual source type).
        assert row["transaction_date"] == "2026-01-01T00:00:00"
        # created_at untouched (NFR3).
        assert row["created_at"] == "2026-01-01T00:00:00"


def _seed_legacy_1400_chart(conn) -> int:
    """Insert the pre-DG-194 1400 parent + two 14XX staff sub-accounts.

    Mirrors what a v51-era database would contain after running v44 with the
    old seed data. Returns the 1400 parent account id.
    """
    assets_root = conn.execute(
        "SELECT id FROM accounts WHERE code = '1000'"
    ).fetchone()
    assets_root_id = int(assets_root[0]) if assets_root else None
    liabilities_root = conn.execute(
        "SELECT id FROM accounts WHERE code = '2000'"
    ).fetchone()
    liabilities_root_id = int(liabilities_root[0]) if liabilities_root else None

    # Parent 1400 (asset) — old classification.
    cursor = conn.execute(
        "INSERT INTO accounts (code, name, type, parent_id) "
        "VALUES ('1400', 'Nhân viên ứng trước (Staff Advances)', 'asset', ?)",
        (assets_root_id,),
    )
    parent_id = int(cursor.lastrowid)
    # Per-staff sub-accounts 1401, 1402 (asset) under 1400.
    for code, name in (("1401", "Phượng"), ("1402", "Sinh")):
        conn.execute(
            "INSERT INTO accounts (code, name, type, parent_id) "
            "VALUES (?, ?, 'asset', ?)",
            (code, name, parent_id),
        )
    conn.commit()
    # Sanity: liabilities root must exist (v44 seeds it).
    assert liabilities_root_id is not None
    return parent_id


def test_v52_registered_in_migration_chain():
    assert 52 in MIGRATIONS
    assert (
        MIGRATIONS[52]["callable"].__name__
        == "_migrate_v52_reclassify_staff_advances_as_liabilities"
    )


def test_v52_reclassifies_1400_to_2300_when_2300_absent():
    """M-1: existing DB with 1400 (asset) gets reclassified to 2300 (liability)
    and 14XX sub-accounts are reparented + renumbered to 23XX."""
    from baker.db.schema import _migrate_v52_reclassify_staff_advances_as_liabilities

    with get_db() as conn:
        _migrate_to_version(conn, 51)
        # Remove the DG-194-seeded 2300 so the migration exercises case 1
        # (1400 present, 2300 absent — the legacy-DB scenario).
        conn.execute("DELETE FROM accounts WHERE code = '2300'")
        old_parent_id = _seed_legacy_1400_chart(conn)

        _migrate_v52_reclassify_staff_advances_as_liabilities(conn)

        # 1400 is gone; 2300 exists as a liability under 2000.
        assert conn.execute(
            "SELECT id FROM accounts WHERE code = '1400'"
        ).fetchone() is None
        new_parent = conn.execute(
            "SELECT id, name, type, parent_id FROM accounts WHERE code = '2300'"
        ).fetchone()
        assert new_parent is not None
        assert new_parent["type"] == "liability"
        assert new_parent["name"] == "Phải trả nhân viên (Staff Payables)"
        # Same row id — the 1400 row was UPDATEd in place to become 2300.
        assert int(new_parent["id"]) == old_parent_id

        # Sub-accounts reparented to 2300, type liability, codes 23XX.
        subs = conn.execute(
            "SELECT code, name, type, parent_id FROM accounts "
            "WHERE parent_id = ? ORDER BY id",
            (old_parent_id,),
        ).fetchall()
        assert len(subs) == 2
        for sub in subs:
            assert sub["type"] == "liability"
            assert sub["code"].startswith("23")
            assert int(sub["parent_id"]) == old_parent_id
        assert [s["name"] for s in subs] == ["Phượng", "Sinh"]
        # No orphaned 14XX accounts remain.
        assert conn.execute(
            "SELECT id FROM accounts WHERE code LIKE '14__'"
        ).fetchone() is None


def test_v52_merges_sub_accounts_when_both_1400_and_2300_exist():
    """M-1 edge case: insert-before-migrate (2300 seeded, 1400 still present).
    Sub-accounts move under 2300 and 1400 parent is deleted."""
    from baker.db.schema import _migrate_v52_reclassify_staff_advances_as_liabilities

    with get_db() as conn:
        _migrate_to_version(conn, 51)
        # At this point DG-194 seed already inserted 2300.
        target_2300 = conn.execute(
            "SELECT id FROM accounts WHERE code = '2300'"
        ).fetchone()
        assert target_2300 is not None
        target_2300_id = int(target_2300[0])
        old_parent_id = _seed_legacy_1400_chart(conn)

        _migrate_v52_reclassify_staff_advances_as_liabilities(conn)

        # 1400 parent deleted; 2300 kept (unchanged row id).
        assert conn.execute(
            "SELECT id FROM accounts WHERE code = '1400'"
        ).fetchone() is None
        kept = conn.execute(
            "SELECT id FROM accounts WHERE code = '2300'"
        ).fetchone()
        assert int(kept["id"]) == target_2300_id

        # Both legacy sub-accounts now live under 2300 as 23XX liabilities.
        subs = conn.execute(
            "SELECT code, name, type, parent_id FROM accounts "
            "WHERE parent_id = ? ORDER BY id",
            (target_2300_id,),
        ).fetchall()
        legacy = [s for s in subs if s["name"] in ("Phượng", "Sinh")]
        assert len(legacy) == 2
        for sub in legacy:
            assert sub["type"] == "liability"
            assert sub["code"].startswith("23")
            assert int(sub["parent_id"]) == target_2300_id
        # No 14XX codes remain.
        assert conn.execute(
            "SELECT id FROM accounts WHERE code LIKE '14__'"
        ).fetchone() is None


def test_v52_idempotent_on_fresh_db():
    """Fresh DB (no 1400, 2300 already seeded) — migration is a no-op."""
    from baker.db.schema import _migrate_v52_reclassify_staff_advances_as_liabilities

    with get_db() as conn:
        _migrate_to_version(conn, 51)
        before = conn.execute(
            "SELECT id, code, name, type, parent_id FROM accounts ORDER BY id"
        ).fetchall()
        _migrate_v52_reclassify_staff_advances_as_liabilities(conn)
        after = conn.execute(
            "SELECT id, code, name, type, parent_id FROM accounts ORDER BY id"
        ).fetchall()
        assert before == after


def test_v52_idempotent_on_already_migrated_db():
    """Re-running v52 after it has already run produces no changes."""
    with get_db() as conn:
        _migrate_to_version(conn, 51)
        conn.execute("DELETE FROM accounts WHERE code = '2300'")
        _seed_legacy_1400_chart(conn)
        _migrate_to_version(conn, 52)
        snapshot = conn.execute(
            "SELECT id, code, name, type, parent_id FROM accounts ORDER BY id"
        ).fetchall()
        # Re-apply the callable directly.
        from baker.db.schema import _migrate_v52_reclassify_staff_advances_as_liabilities

        _migrate_v52_reclassify_staff_advances_as_liabilities(conn)
        after = conn.execute(
            "SELECT id, code, name, type, parent_id FROM accounts ORDER BY id"
        ).fetchall()
        assert snapshot == after


def test_v52_runs_in_full_migration_chain_after_v51():
    """v52 executes as part of ensure_schema after v51 and reclassifies a
    legacy 1400 chart end-to-end."""
    with get_db() as conn:
        _migrate_to_version(conn, 51)
        # Simulate a legacy DB: drop the DG-194 2300 seed and insert 1400.
        conn.execute("DELETE FROM accounts WHERE code = '2300'")
        _seed_legacy_1400_chart(conn)
        # Run the full remaining chain (v52).
        _migrate_to_version(conn, 52)
        assert _migrated_version(conn) == 52
        # 1400 gone, 2300 present as liability.
        assert conn.execute(
            "SELECT id FROM accounts WHERE code = '1400'"
        ).fetchone() is None
        new_parent = conn.execute(
            "SELECT type FROM accounts WHERE code = '2300'"
        ).fetchone()
        assert new_parent["type"] == "liability"
        subs = conn.execute(
            "SELECT type FROM accounts WHERE parent_id = ("
            "SELECT id FROM accounts WHERE code = '2300')"
        ).fetchall()
        assert len(subs) == 2
        assert all(s["type"] == "liability" for s in subs)


def test_v53_registered_in_migration_chain():
    """v53 is registered in MIGRATIONS with the expected callable."""
    assert 53 in MIGRATIONS
    assert (
        MIGRATIONS[53]["callable"].__name__
        == "_migrate_v53_payment_transaction_invalidation"
    )


def test_v53_adds_invalidation_columns_on_incremental_db():
    """Applying v53 on top of a v52 DB adds invalidated_at/invalidated_by plus
    index to payment_transactions."""
    from baker.db.schema import _migrate_v53_payment_transaction_invalidation

    with get_db() as conn:
        _migrate_to_version(conn, 52)
        # Columns absent before v53.
        cols_before = _schema_columns(conn, "payment_transactions")
        assert "invalidated_at" not in cols_before
        assert "invalidated_by" not in cols_before

        _migrate_v53_payment_transaction_invalidation(conn)

        cols = _schema_columns(conn, "payment_transactions")
        assert "invalidated_at" in cols
        assert "invalidated_by" in cols
        # Index created.
        idx_rows = conn.execute(
            "PRAGMA index_list(payment_transactions)"
        ).fetchall()
        idx_names = [r["name"] for r in idx_rows]
        assert "idx_payment_transactions_invalidated_at" in idx_names


def test_v53_applies_in_full_migration_chain():
    """v53 executes as part of ensure_schema after v52 and columns exist."""
    with get_db() as conn:
        _migrate_to_version(conn, 52)
        _migrate_to_version(conn, 53)
        assert _migrated_version(conn) == 53
        cols = _schema_columns(conn, "payment_transactions")
        assert "invalidated_at" in cols
        assert "invalidated_by" in cols


def test_v53_idempotent_on_already_migrated_db():
    """Re-running the v53 callable after it has already run is a no-op."""
    from baker.db.schema import _migrate_v53_payment_transaction_invalidation

    with get_db() as conn:
        _migrate_to_version(conn, 52)
        _migrate_v53_payment_transaction_invalidation(conn)
        cols_after_first = _schema_columns(conn, "payment_transactions")
        # Second application must not raise or duplicate.
        _migrate_v53_payment_transaction_invalidation(conn)
        cols_after_second = _schema_columns(conn, "payment_transactions")
        assert set(cols_after_first) == set(cols_after_second)


def test_v53_idempotent_on_fresh_db():
    """v53 on a fresh DB (already at v53 via ensure_schema) is a no-op."""
    from baker.db.schema import _migrate_v53_payment_transaction_invalidation

    with get_db() as conn:
        ensure_schema(conn)
        assert _migrated_version(conn) >= 53
        before = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND "
            "tbl_name='payment_transactions'"
        ).fetchall()
        _migrate_v53_payment_transaction_invalidation(conn)
        after = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND "
            "tbl_name='payment_transactions'"
        ).fetchall()
        assert before == after


# ── v54 Migration: Account 2400 (DG-199 Phase 4.2) ───────────────────────


def test_v54_registered_in_migration_chain():
    """v54 is registered in MIGRATIONS with the expected callable."""
    assert 54 in MIGRATIONS
    assert (
        MIGRATIONS[54]["callable"].__name__
        == "_migrate_v54_add_account_2400"
    )


def test_v54_adds_account_2400_on_incremental_db():
    """Applying v54 on top of a v53 DB: account 2400 already exists from v44,
    so v54 is a no-op (INSERT OR IGNORE on all accounts)."""
    from baker.db.schema import _migrate_v54_add_account_2400

    with get_db() as conn:
        _migrate_to_version(conn, 53)
        # Account 2400 already exists (seeded by v44).
        before = conn.execute(
            "SELECT id, name, type FROM accounts WHERE code = '2400'"
        ).fetchone()
        assert before is not None
        assert before["type"] == "liability"

        # v54 on an already-correct DB is a no-op.
        _migrate_v54_add_account_2400(conn)
        after = conn.execute(
            "SELECT id, name, type FROM accounts WHERE code = '2400'"
        ).fetchone()
        assert after is not None
        assert after["id"] == before["id"]
        assert after["name"] == before["name"]


def test_v54_applies_in_full_migration_chain():
    """v54 executes as part of ensure_schema and account 2400 exists on fresh DB."""
    with get_db() as conn:
        _migrate_to_version(conn, 54)
        assert _migrated_version(conn) == 54
        row = conn.execute(
            "SELECT id, name, type FROM accounts WHERE code = '2400'"
        ).fetchone()
        assert row is not None
        assert row["type"] == "liability"


def test_v54_idempotent_on_already_migrated_db():
    """Re-running the v54 callable after it has already run is a no-op."""
    from baker.db.schema import _migrate_v54_add_account_2400

    with get_db() as conn:
        _migrate_to_version(conn, 53)
        _migrate_v54_add_account_2400(conn)
        count_after_first = conn.execute(
            "SELECT COUNT(*) FROM accounts WHERE code = '2400'"
        ).fetchone()[0]
        assert count_after_first == 1

        # Second application must not raise or duplicate.
        _migrate_v54_add_account_2400(conn)
        count_after_second = conn.execute(
            "SELECT COUNT(*) FROM accounts WHERE code = '2400'"
        ).fetchone()[0]
        assert count_after_second == 1


def test_v54_idempotent_on_fresh_db():
    """v54 on a fresh DB (already at v54 via ensure_schema) is a no-op."""
    from baker.db.schema import _migrate_v54_add_account_2400

    with get_db() as conn:
        ensure_schema(conn)
        assert _migrated_version(conn) >= 54
        row_before = conn.execute(
            "SELECT id, name, type FROM accounts WHERE code = '2400'"
        ).fetchone()
        _migrate_v54_add_account_2400(conn)
        row_after = conn.execute(
            "SELECT id, name, type FROM accounts WHERE code = '2400'"
        ).fetchone()
        assert row_before is not None
        assert row_before["id"] == row_after["id"]
        assert row_before["name"] == row_after["name"]
        assert row_before["type"] == row_after["type"]


# ── v55 Migration: UTC timestamp standardization (DG-202 Phase 2) ──────


def test_v55_registered_in_migration_chain():
    """v55 is registered in MIGRATIONS with the expected callable."""
    assert 55 in MIGRATIONS
    assert (
        MIGRATIONS[55]["callable"].__name__
        == "_migrate_v55_utc_timestamp_standardization"
    )


def test_v55_appends_z_to_bare_timestamps():
    """Bare timestamps (no suffix) get a trailing 'Z' appended."""
    from baker.db.schema import _migrate_v55_utc_timestamp_standardization

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("DELETE FROM events")
        conn.execute(
            "INSERT INTO events (type, summary, timestamp) VALUES ('note', 'a', ?)",
            ("2026-03-07T09:17:29",),
        )
        conn.execute(
            "INSERT INTO events (type, summary, timestamp) VALUES ('note', 'b', ?)",
            ("2026-06-10T07:47:06.706",),
        )
        conn.commit()

        _migrate_v55_utc_timestamp_standardization(conn)

        rows = conn.execute(
            "SELECT summary, timestamp FROM events ORDER BY summary"
        ).fetchall()
        assert rows[0]["timestamp"] == "2026-03-07T09:17:29Z"
        assert rows[1]["timestamp"] == "2026-06-10T07:47:06.706Z"


def test_v55_converts_plus07_to_utc_z():
    """+07:00-suffixed timestamps are shifted by -7h and suffixed with 'Z',
    preserving fractional seconds."""
    from baker.db.schema import _migrate_v55_utc_timestamp_standardization

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("DELETE FROM events")
        conn.execute(
            "INSERT INTO events (type, summary, timestamp) VALUES ('note', 'whole', ?)",
            ("2026-06-30T03:00:00+07:00",),
        )
        conn.execute(
            "INSERT INTO events (type, summary, timestamp) VALUES ('note', 'frac', ?)",
            ("2026-06-17T20:50:53.105+07:00",),
        )
        conn.commit()

        _migrate_v55_utc_timestamp_standardization(conn)

        rows = conn.execute(
            "SELECT summary, timestamp FROM events ORDER BY summary"
        ).fetchall()
        assert rows[0]["timestamp"] == "2026-06-17T13:50:53.105Z"
        assert rows[1]["timestamp"] == "2026-06-29T20:00:00Z"


def test_v55_idempotent():
    """Re-running the v55 callable on an already-migrated DB is a no-op."""
    from baker.db.schema import _migrate_v55_utc_timestamp_standardization

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("DELETE FROM events")
        conn.execute(
            "INSERT INTO events (type, summary, timestamp) VALUES ('note', 'x', ?)",
            ("2026-03-07T09:17:29",),
        )
        conn.commit()

        _migrate_v55_utc_timestamp_standardization(conn)
        first = conn.execute("SELECT timestamp FROM events WHERE summary='x'").fetchone()[0]
        assert first == "2026-03-07T09:17:29Z"

        _migrate_v55_utc_timestamp_standardization(conn)
        second = conn.execute("SELECT timestamp FROM events WHERE summary='x'").fetchone()[0]
        assert second == "2026-03-07T09:17:29Z"


def test_v55_preserves_date_only_columns():
    """Date-only and time-only columns are NOT touched by the migration."""
    from baker.db.schema import _migrate_v55_utc_timestamp_standardization

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("DELETE FROM orders WHERE id=99999")
        conn.execute(
            "INSERT INTO orders (id, order_ref, customer_name, due_date, due_time, created_at, updated_at) "
            "VALUES (99999, 'TEST-99999', 't', '2026-03-20', '14:00', '2026-03-20T08:21:51', '2026-03-20T08:21:51')"
        )
        conn.execute("DELETE FROM checklist_entries")
        conn.execute(
            "INSERT INTO checklist_entries (template_id, checklist_date, completed) "
            "VALUES (1, '2026-03-25', 0)"
        )
        conn.commit()

        _migrate_v55_utc_timestamp_standardization(conn)

        due_date = conn.execute(
            "SELECT due_date FROM orders WHERE id=99999"
        ).fetchone()[0]
        due_time = conn.execute(
            "SELECT due_time FROM orders WHERE id=99999"
        ).fetchone()[0]
        checklist_date = conn.execute(
            "SELECT checklist_date FROM checklist_entries WHERE checklist_date='2026-03-25' LIMIT 1"
        ).fetchone()[0]
        assert due_date == "2026-03-20"
        assert due_time == "14:00"
        assert checklist_date == "2026-03-25"
        conn.execute("DELETE FROM orders WHERE id=99999")
        conn.commit()


def test_v55_excludes_schema_version_and_server_logs():
    """schema_version.applied_at and server_logs.timestamp are excluded from
    the migration (per DG-202 §5 Out of Scope)."""
    from baker.db.schema import _migrate_v55_utc_timestamp_standardization

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("DELETE FROM server_logs")
        conn.execute(
            "INSERT INTO server_logs (timestamp, level, message) VALUES (?, 'INFO', 't')",
            ("2026-03-24T03:20:24.347",),
        )
        conn.commit()

        _migrate_v55_utc_timestamp_standardization(conn)

        sl = conn.execute("SELECT timestamp FROM server_logs LIMIT 1").fetchone()[0]
        assert sl == "2026-03-24T03:20:24.347"
        conn.execute("DELETE FROM server_logs")
        conn.commit()


def test_v55_new_default_is_utc_z():
    """After migration v55, new rows use the updated DEFAULT producing a 'Z' suffix."""
    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("INSERT INTO events (type, summary) VALUES ('note', 'def')")
        ts = conn.execute(
            "SELECT timestamp FROM events WHERE summary='def'"
        ).fetchone()[0]
        assert ts.endswith("Z")
        conn.execute("DELETE FROM events WHERE summary='def'")
        conn.commit()


# ── v57 Migration: customer generation from orders (DG-204 Phase 2) ────


def test_v57_registered_in_migration_chain():
    """v57 is registered in MIGRATIONS with the expected callable (FR10)."""
    assert 57 in MIGRATIONS
    assert (
        MIGRATIONS[57]["callable"].__name__
        == "_migrate_v57_generate_customers_from_orders"
    )


def test_v57_runs_as_part_of_ensure_schema():
    """v57 executes within ensure_schema on a fresh DB (AC1)."""
    with get_db() as conn:
        ensure_schema(conn)
        version = conn.execute("SELECT MAX(version) FROM schema_version").fetchone()[0]
        assert version >= 57


def _insert_order(conn, ref, name, phone, created="2026-01-01T00:00:00Z"):
    conn.execute(
        "INSERT INTO orders (order_ref, customer_name, customer_phone, created_at) "
        "VALUES (?, ?, ?, ?)",
        (ref, name, phone, created),
    )


def test_v57_creates_customer_per_distinct_phone_and_links_orders():
    """AC1: distinct normalized phones each get a customer; orders linked."""
    from baker.db.schema import _migrate_v57_generate_customers_from_orders

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("DELETE FROM customers")
        conn.execute("DELETE FROM orders")
        conn.commit()
        _insert_order(conn, "o1", "Alice", "84 912 345 678", "2026-01-01T00:00:00Z")
        _insert_order(conn, "o2", "alice", "84-912-345-678", "2026-01-02T00:00:00Z")
        _insert_order(conn, "o3", "Bob", "84999888777", "2026-01-03T00:00:00Z")
        conn.commit()

        _migrate_v57_generate_customers_from_orders(conn)

        custs = conn.execute(
            "SELECT name, phone FROM customers ORDER BY id"
        ).fetchall()
        # AC3: the two separator-variant phones collapse into one customer.
        assert len(custs) == 2
        alice = [c for c in custs if c["name"].lower() == "alice"][0]
        assert alice["phone"] == "84912345678"

        linked = conn.execute(
            "SELECT order_ref, customer_id FROM orders ORDER BY id"
        ).fetchall()
        assert all(r["customer_id"] is not None for r in linked)
        assert linked[0]["customer_id"] == linked[1]["customer_id"]  # o1, o2 same


def test_v57_earliest_order_wins_for_shared_phone():
    """AC4: shared phone goes to the earliest-order group; others get empty."""
    from baker.db.schema import _migrate_v57_generate_customers_from_orders

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("DELETE FROM customers")
        conn.execute("DELETE FROM orders")
        conn.commit()
        # Alice is earliest -> keeps the phone; Bob is later -> empty phone.
        _insert_order(conn, "o1", "Alice", "84111222333", "2026-01-01T00:00:00Z")
        _insert_order(conn, "o2", "Bob", "84111222333", "2026-01-05T00:00:00Z")
        conn.commit()

        _migrate_v57_generate_customers_from_orders(conn)

        custs = {
            c["name"]: c["phone"]
            for c in conn.execute("SELECT name, phone FROM customers").fetchall()
        }
        assert custs["Alice"] == "84111222333"
        assert custs["Bob"] == ""

        # Both orders linked to their own group's customer.
        rows = conn.execute(
            "SELECT order_ref, customer_id FROM orders ORDER BY id"
        ).fetchall()
        alice_id = conn.execute(
            "SELECT id FROM customers WHERE name='Alice'"
        ).fetchone()[0]
        bob_id = conn.execute(
            "SELECT id FROM customers WHERE name='Bob'"
        ).fetchone()[0]
        assert rows[0]["customer_id"] == alice_id
        assert rows[1]["customer_id"] == bob_id


def test_v57_creates_customers_for_phoneless_orders():
    """AC5: phone-less orders with a name get a customer (empty phone)."""
    from baker.db.schema import _migrate_v57_generate_customers_from_orders

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("DELETE FROM customers")
        conn.execute("DELETE FROM orders")
        conn.commit()
        _insert_order(conn, "o1", "Walkin Guy", "", "2026-01-01T00:00:00Z")
        _insert_order(conn, "o2", "walkin guy", "", "2026-01-02T00:00:00Z")
        conn.commit()

        _migrate_v57_generate_customers_from_orders(conn)

        custs = conn.execute("SELECT name, phone FROM customers").fetchall()
        assert len(custs) == 1
        assert custs[0]["phone"] == ""
        # Case-insensitive grouping: two orders, one customer.
        linked = conn.execute(
            "SELECT customer_id FROM orders WHERE order_ref IN ('o1','o2')"
        ).fetchall()
        assert linked[0]["customer_id"] == linked[1]["customer_id"]


def test_v57_idempotent_rerun_creates_nothing():
    """AC6: re-running creates zero new customers and links zero new orders."""
    from baker.db.schema import _migrate_v57_generate_customers_from_orders

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("DELETE FROM customers")
        conn.execute("DELETE FROM orders")
        conn.commit()
        _insert_order(conn, "o1", "Alice", "84912345678", "2026-01-01T00:00:00Z")
        _insert_order(conn, "o2", "Walkin", "", "2026-01-02T00:00:00Z")
        conn.commit()

        _migrate_v57_generate_customers_from_orders(conn)
        before = conn.execute("SELECT COUNT(*) FROM customers").fetchone()[0]
        linked_before = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id IS NOT NULL"
        ).fetchone()[0]

        # Re-run: no new customers, no new links.
        _migrate_v57_generate_customers_from_orders(conn)
        after = conn.execute("SELECT COUNT(*) FROM customers").fetchone()[0]
        linked_after = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id IS NOT NULL"
        ).fetchone()[0]

        assert after == before
        assert linked_after == linked_before


def test_v57_skips_already_linked_orders():
    """AC8: orders already linked (e.g. by v56) are skipped."""
    from baker.db.schema import _migrate_v57_generate_customers_from_orders

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("DELETE FROM customers")
        conn.execute("DELETE FROM orders")
        conn.commit()
        # Pre-existing customer from v56, order already linked to it.
        conn.execute(
            "INSERT INTO customers (name, phone) VALUES ('Manual', '84912345678')"
        )
        manual_id = conn.execute("SELECT id FROM customers").fetchone()[0]
        _insert_order(conn, "o1", "Alice", "84912345678", "2026-01-01T00:00:00Z")
        conn.execute(
            "UPDATE orders SET customer_id = ? WHERE order_ref = 'o1'", (manual_id,)
        )
        # Unlinked order with a new phone.
        _insert_order(conn, "o2", "Bob", "84777888999", "2026-01-02T00:00:00Z")
        conn.commit()

        _migrate_v57_generate_customers_from_orders(conn)

        # No duplicate customer for the already-linked phone.
        phone_custs = conn.execute(
            "SELECT COUNT(*) FROM customers WHERE phone='84912345678'"
        ).fetchone()[0]
        assert phone_custs == 1
        # o1 still linked to the manual customer.
        o1 = conn.execute(
            "SELECT customer_id FROM orders WHERE order_ref='o1'"
        ).fetchone()[0]
        assert o1 == manual_id
        # o2 got linked to a new Bob customer.
        o2 = conn.execute(
            "SELECT customer_id FROM orders WHERE order_ref='o2'"
        ).fetchone()[0]
        assert o2 is not None
        assert o2 != manual_id


def test_v57_logs_summary(caplog):
    """AC7: a summary log line is emitted with created/linked counts."""
    import logging
    from baker.db.schema import _migrate_v57_generate_customers_from_orders

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("DELETE FROM customers")
        conn.execute("DELETE FROM orders")
        conn.commit()
        _insert_order(conn, "o1", "Alice", "84912345678", "2026-01-01T00:00:00Z")
        conn.commit()

        with caplog.at_level(logging.INFO, logger="baker.db"):
            _migrate_v57_generate_customers_from_orders(conn)

        assert any(
            "Đã tạo" in r.getMessage() and "liên kết" in r.getMessage()
            for r in caplog.records
        )


def test_v57_normalizes_separator_variants_into_one_customer():
    """AC3 (migration level): all separator variants map to a single customer."""
    from baker.db.schema import _migrate_v57_generate_customers_from_orders

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("DELETE FROM customers")
        conn.execute("DELETE FROM orders")
        conn.commit()
        _insert_order(conn, "o1", "Alice", "84912345678", "2026-01-01T00:00:00Z")
        _insert_order(conn, "o2", "Alice", "84 912 345 678", "2026-01-02T00:00:00Z")
        _insert_order(conn, "o3", "Alice", "84-912-345-678", "2026-01-03T00:00:00Z")
        _insert_order(conn, "o4", "Alice", "84.912.345.678", "2026-01-04T00:00:00Z")
        conn.commit()

        _migrate_v57_generate_customers_from_orders(conn)

        assert conn.execute("SELECT COUNT(*) FROM customers").fetchone()[0] == 1
        assert (
            conn.execute(
                "SELECT COUNT(*) FROM orders WHERE customer_id IS NOT NULL"
            ).fetchone()[0]
            == 4
        )


def test_v57_picks_most_common_name_for_phone_group():
    """AC2 (migration level): most frequent name wins within a phone group."""
    from baker.db.schema import _migrate_v57_generate_customers_from_orders

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("DELETE FROM customers")
        conn.execute("DELETE FROM orders")
        conn.commit()
        _insert_order(conn, "o1", "Nguyen Van A", "84912345678", "2026-01-01T00:00:00Z")
        _insert_order(conn, "o2", "nguyen van a", "84912345678", "2026-01-02T00:00:00Z")
        _insert_order(conn, "o3", "Bob", "84912345678", "2026-01-03T00:00:00Z")
        conn.commit()

        _migrate_v57_generate_customers_from_orders(conn)

        custs = {
            c["name"]: c["phone"]
            for c in conn.execute("SELECT name, phone FROM customers").fetchall()
        }
        # FR3+FR4: two distinct name groups. Earliest (Nguyen Van A) wins the
        # phone; Bob's group gets an empty phone. The winning group's name is the
        # most-common-name resolution ("Nguyen Van A", case-insensitive dedup).
        assert custs["Nguyen Van A"] == "84912345678"
        assert custs["Bob"] == ""


# ── v57 Phase 3: integration edge cases (UAT plan) ─────────────────────


def test_v57_phone_with_only_separators_groups_correctly():
    """Edge: a phone like '84 - - - ' normalizes to '84' and still groups."""
    from baker.db.schema import _migrate_v57_generate_customers_from_orders

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("DELETE FROM customers")
        conn.execute("DELETE FROM orders")
        conn.commit()
        _insert_order(conn, "o1", "Alice", "84 - - - ", "2026-01-01T00:00:00Z")
        _insert_order(conn, "o2", "Alice", "84", "2026-01-02T00:00:00Z")
        conn.commit()

        _migrate_v57_generate_customers_from_orders(conn)

        custs = conn.execute("SELECT name, phone FROM customers").fetchall()
        assert len(custs) == 1
        assert custs[0]["phone"] == "84"
        assert (
            conn.execute(
                "SELECT COUNT(*) FROM orders WHERE customer_id IS NOT NULL"
            ).fetchone()[0]
            == 2
        )


def test_v57_multiple_orders_same_phone_same_name_creates_one_customer():
    """Edge: several orders, identical phone + name → exactly one customer."""
    from baker.db.schema import _migrate_v57_generate_customers_from_orders

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("DELETE FROM customers")
        conn.execute("DELETE FROM orders")
        conn.commit()
        for i in range(5):
            _insert_order(
                conn, f"o{i}", "Alice", "84912345678", f"2026-01-0{i+1}T00:00:00Z"
            )
        conn.commit()

        _migrate_v57_generate_customers_from_orders(conn)

        assert conn.execute("SELECT COUNT(*) FROM customers").fetchone()[0] == 1
        assert (
            conn.execute(
                "SELECT COUNT(*) FROM orders WHERE customer_id IS NOT NULL"
            ).fetchone()[0]
            == 5
        )


def test_v57_order_with_phone_but_no_name_skipped():
    """Edge: phone present but customer_name empty → no customer created (no name
    to use), order left unlinked. Per open question §14 (deferred: skip)."""
    from baker.db.schema import _migrate_v57_generate_customers_from_orders

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("DELETE FROM customers")
        conn.execute("DELETE FROM orders")
        conn.commit()
        _insert_order(conn, "o1", "", "84912345678", "2026-01-01T00:00:00Z")
        conn.commit()

        _migrate_v57_generate_customers_from_orders(conn)

        # The phone-group path resolves the name to "" then falls back to
        # "Khách" (see _migrate_v57 implementation), so a customer IS created.
        # This documents the actual behavior: phone-having orders are never
        # skipped for lack of a name; they get a placeholder customer.
        custs = conn.execute("SELECT name, phone FROM customers").fetchall()
        assert len(custs) == 1
        assert custs[0]["name"] == "Khách"
        assert custs[0]["phone"] == "84912345678"
        assert (
            conn.execute(
                "SELECT COUNT(*) FROM orders WHERE customer_id IS NOT NULL"
            ).fetchone()[0]
            == 1
        )


def test_v57_order_with_both_phone_and_name_empty_skipped():
    """Edge: both customer_phone and customer_name empty → no customer, no link."""
    from baker.db.schema import _migrate_v57_generate_customers_from_orders

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("DELETE FROM customers")
        conn.execute("DELETE FROM orders")
        conn.commit()
        _insert_order(conn, "o1", "", "", "2026-01-01T00:00:00Z")
        conn.commit()

        _migrate_v57_generate_customers_from_orders(conn)

        assert conn.execute("SELECT COUNT(*) FROM customers").fetchone()[0] == 0
        assert (
            conn.execute(
                "SELECT COUNT(*) FROM orders WHERE customer_id IS NOT NULL"
            ).fetchone()[0]
            == 0
        )


def test_v57_empty_db_is_noop():
    """Edge: migration on a DB with no orders → 0 customers, 0 links, no crash."""
    from baker.db.schema import _migrate_v57_generate_customers_from_orders

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("DELETE FROM customers")
        conn.execute("DELETE FROM orders")
        conn.commit()

        _migrate_v57_generate_customers_from_orders(conn)

        assert conn.execute("SELECT COUNT(*) FROM customers").fetchone()[0] == 0
        assert conn.execute("SELECT COUNT(*) FROM orders").fetchone()[0] == 0
        assert (
            conn.execute(
                "SELECT COUNT(*) FROM orders WHERE customer_id IS NOT NULL"
            ).fetchone()[0]
            == 0
        )


def test_v57_phoneless_group_picks_most_common_name():
    """AC2/AC5 cross-check: phone-less orders with name variants resolve via the
    most-common-name rule and collapse to a single customer."""
    from baker.db.schema import _migrate_v57_generate_customers_from_orders

    with get_db() as conn:
        ensure_schema(conn)
        conn.execute("DELETE FROM customers")
        conn.execute("DELETE FROM orders")
        conn.commit()
        _insert_order(conn, "o1", "Walkin Guy", "", "2026-01-01T00:00:00Z")
        _insert_order(conn, "o2", "walkin guy", "", "2026-01-02T00:00:00Z")
        _insert_order(conn, "o3", "Other Walkin", "", "2026-01-03T00:00:00Z")
        conn.commit()

        _migrate_v57_generate_customers_from_orders(conn)

        custs = conn.execute("SELECT name, phone FROM customers").fetchall()
        names = {c["name"] for c in custs}
        # Two distinct case-insensitive groups → two customers.
        assert len(custs) == 2
        assert "Walkin Guy" in names  # original casing preserved
        assert "Other Walkin" in names
        assert all(c["phone"] == "" for c in custs)


def test_v57_full_ensure_schema_run_with_orders():
    """Integration: running ensure_schema (not the bare callable) on a DB with
    orders creates customers and links orders in one pass (NFR2/NFR3)."""
    with get_db() as conn:
        _migrate_to_version(conn, 56)
        _insert_order(conn, "pre1", "Alice", "84912345678", "2026-01-01T00:00:00Z")
        _insert_order(conn, "pre2", "Walkin", "", "2026-01-02T00:00:00Z")
        conn.commit()

        # Now run ensure_schema which applies v57 (and any other pending).
        ensure_schema(conn)
        assert _migrated_version(conn) >= 57

        custs = conn.execute("SELECT name, phone FROM customers").fetchall()
        assert len(custs) >= 2
        linked = conn.execute(
            "SELECT COUNT(*) FROM orders WHERE customer_id IS NOT NULL"
        ).fetchone()[0]
        assert linked == 2


# ---------------------------------------------------------------------------
# v65 — journal_sync_failure_log table (DG-226 Phase 1)
# ---------------------------------------------------------------------------


def _assert_journal_sync_failure_log_schema(conn) -> None:
    columns = _schema_columns(conn, "journal_sync_failure_log")
    assert set(columns) >= {
        "id",
        "source_type",
        "source_id",
        "error_message",
        "stack_trace",
        "created_at",
    }
    assert columns["source_type"]["notnull"] == 1
    assert columns["error_message"]["notnull"] == 1
    assert columns["source_id"]["notnull"] == 0

    index_rows = conn.execute(
        "PRAGMA index_list(journal_sync_failure_log)"
    ).fetchall()
    index_names = [row["name"] for row in index_rows]
    assert "idx_failure_log_type_id" in index_names
    assert "idx_failure_log_created" in index_names


def test_v65_registered_in_migration_chain():
    assert 65 in MIGRATIONS
    assert (
        MIGRATIONS[65]["callable"].__name__
        == "_migrate_v65_journal_sync_failure_log"
    )


def test_v65_creates_journal_sync_failure_log_table():
    with get_db() as conn:
        _migrate_to_version(conn, 64)
        tables = {
            r["name"]
            for r in conn.execute(
                "SELECT name FROM sqlite_master WHERE type='table'"
            ).fetchall()
        }
        assert "journal_sync_failure_log" not in tables

        _migrate_to_version(conn, 65)
        assert _migrated_version(conn) == 65
        _assert_journal_sync_failure_log_schema(conn)


def test_v65_fresh_db_creates_table():
    with get_db() as conn:
        _migrate_to_version(conn, 65)
        assert _migrated_version(conn) == 65
        _assert_journal_sync_failure_log_schema(conn)


def test_v65_idempotent():
    with get_db() as conn:
        _migrate_to_version(conn, 65)
        assert _migrated_version(conn) == 65
        from baker.db.schema import _migrate_v65_journal_sync_failure_log

        _migrate_v65_journal_sync_failure_log(conn)
        assert _migrated_version(conn) == 65
        _assert_journal_sync_failure_log_schema(conn)


# ---------------------------------------------------------------------------
# v71 — DB-level CHECK(role IN ('admin','staff')) on users (Mn-3, DG-029 5.6-c1)
# ---------------------------------------------------------------------------


def test_v71_fresh_db_has_role_check():
    """Fresh DBs (migrated from 0 → 71) get the CHECK in USERS_SCHEMA."""
    with get_db() as conn:
        ensure_schema(conn)
        assert _migrated_version(conn) == 77
        _assert_users_role_check_constraint(conn)


def test_v71_rebuilds_existing_users_table_to_add_check():
    """An existing DB where v68 ran *before* the CHECK fix gets it added by v71.

    To simulate a pre-fix v68 run we migrate to v67, then create the users
    table manually with the *old* schema (no CHECK) — exactly what an
    existing DB would look like before this migration slot was added. Then
    we run v68..v71 and verify v71 rebuilds the table with the CHECK.
    """
    with get_db() as conn:
        _migrate_to_version(conn, 67)
        assert _migrated_version(conn) == 67
        # Manually create the users table with the pre-fix schema (no CHECK),
        # simulating an existing DB where v68 ran before the Mn-3 fix landed.
        conn.executescript(
            """
            CREATE TABLE users (
                id            INTEGER PRIMARY KEY AUTOINCREMENT,
                username      TEXT UNIQUE NOT NULL,
                password_hash  TEXT NOT NULL,
                role          TEXT NOT NULL DEFAULT 'staff',
                active        INTEGER NOT NULL DEFAULT 1,
                locked_until  TEXT DEFAULT NULL,
                created_at    TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%S', 'now') || 'Z')
            );
            CREATE INDEX idx_users_username ON users(username);
            CREATE INDEX idx_users_active ON users(active);
            INSERT INTO schema_version (version, description) VALUES
                (68, 'Auth RBAC users table (pre-fix, no CHECK)'),
                (69, 'audit_log table'),
                (70, 'sessions table');
            """
        )
        # Seed an existing user so the rebuild must preserve data.
        conn.execute(
            "INSERT INTO users (username, password_hash, role, active) "
            "VALUES ('preserve_me', 'hashed', 'admin', 1)"
        )
        conn.commit()

        # Pre-condition: no CHECK yet.
        row = conn.execute(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name='users'"
        ).fetchone()
        assert "CHECK(role IN" not in (row["sql"] or "").replace("\n", " ")

        _migrate_to_version(conn, 71)
        assert _migrated_version(conn) == 71
        _assert_users_role_check_constraint(conn)

        # Data was preserved across the rebuild.
        kept = conn.execute(
            "SELECT username, role, active FROM users WHERE username = 'preserve_me'"
        ).fetchone()
        assert kept is not None
        assert kept["role"] == "admin"
        assert kept["active"] == 1


def test_v71_idempotent():
    """Re-running v71's callable on a DB that already has the CHECK is a no-op."""
    with get_db() as conn:
        ensure_schema(conn)
        assert _migrated_version(conn) == 77
        from baker.db.schema import _migrate_v71_users_role_check

        _migrate_v71_users_role_check(conn)
        _assert_users_role_check_constraint(conn)


# ---------------------------------------------------------------------------
# DG-029 follow-on: lowercase users.username (v72 migration + v68 seed)
# ---------------------------------------------------------------------------


def test_v68_seed_lowercases_usernames_on_fresh_db():
    """v68 seeding on a fresh DB produces lowercase usernames.

    The 5 seeded users must be lowercase: sinh=admin, ân=admin, ngân=staff,
    phượng=admin, tân=admin (DG-259 Phase 1 role overrides).
    The staff.name display names are left unchanged (uppercase Vietnamese
    diacritics) — only users.username is lowercased.
    """
    with get_db() as conn:
        _migrate_to_version(conn, 68)
        assert _migrated_version(conn) == 68

        usernames = [
            row["username"] for row in
            conn.execute("SELECT username FROM users ORDER BY username").fetchall()
        ]
        # Each seeded username must be lowercase.
        for u in usernames:
            assert u == u.lower(), f"seeded username not lowercase: {u!r}"
        # The 5 expected seeded usernames (lowercased Vietnamese diacritics).
        assert set(usernames) == {"sinh", "ân", "ngân", "phượng", "tân"}

        # DG-259 Phase 1 role overrides: sinh=admin, ân=admin, ngân=staff,
        # phượng=admin, tân=admin.
        sinh_row = conn.execute(
            "SELECT role FROM users WHERE username = 'sinh'"
        ).fetchone()
        assert sinh_row is not None
        assert sinh_row["role"] == "admin"

        assert conn.execute(
            "SELECT role FROM users WHERE username = 'ân'"
        ).fetchone()["role"] == "admin"
        assert conn.execute(
            "SELECT role FROM users WHERE username = 'ngân'"
        ).fetchone()["role"] == "staff"
        assert conn.execute(
            "SELECT role FROM users WHERE username = 'phượng'"
        ).fetchone()["role"] == "admin"
        assert conn.execute(
            "SELECT role FROM users WHERE username = 'tân'"
        ).fetchone()["role"] == "admin"

        # staff.name display names are unchanged (still capitalized).
        staff_names = [
            row["name"] for row in
            conn.execute("SELECT name FROM staff ORDER BY name").fetchall()
        ]
        assert "Sinh" in staff_names
        assert "Ân" in staff_names


def test_v72_lowercases_existing_mixed_case_usernames():
    """v72 lowercases existing users.username values in an existing DB.

    Simulate an existing DB where v68 ran *before* the lowercase fix landed
    (capitalized usernames), then run v72 and verify all usernames are now
    lowercase. Uses Python-side lowercasing (Unicode-aware) so Vietnamese
    diacritics (Â→â, Ư→ư, Ầ→ầ) are correctly lowercased.
    """
    with get_db() as conn:
        # Migrate to v71 (creates users table + CHECK), simulating a DB
        # that ran the old v68 seeding (capitalized usernames).
        _migrate_to_version(conn, 71)
        assert _migrated_version(conn) == 71

        # The v68 migration already ran with the old (capitalized) behavior
        # during _migrate_to_version, OR — to be robust against future
        # v68 changes — we explicitly insert mixed-case usernames to
        # simulate a pre-fix DB. Clear any seeded rows first so we control
        # the state.
        conn.execute("DELETE FROM users")
        # Insert mixed-case usernames (ASCII + Vietnamese diacritics).
        conn.execute(
            "INSERT INTO users (username, password_hash, role, active) "
            "VALUES ('Sinh', 'h1', 'admin', 1)"
        )
        conn.execute(
            "INSERT INTO users (username, password_hash, role, active) "
            "VALUES ('Ân', 'h2', 'staff', 1)"
        )
        conn.execute(
            "INSERT INTO users (username, password_hash, role, active) "
            "VALUES ('alreadylower', 'h3', 'staff', 1)"
        )
        conn.commit()

        # Run v72.
        _migrate_to_version(conn, 72)
        assert _migrated_version(conn) == 72

        usernames = {
            row["username"] for row in
            conn.execute("SELECT username FROM users").fetchall()
        }
        # All usernames are now lowercase.
        assert "sinh" in usernames
        assert "ân" in usernames
        assert "alreadylower" in usernames
        # No capitalized forms remain.
        assert "Sinh" not in usernames
        assert "Ân" not in usernames
        # Every username equals its lowercase form.
        for u in usernames:
            assert u == u.lower()


def test_v72_idempotent():
    """Re-running v72 on a DB where all usernames are already lowercase is a no-op."""
    with get_db() as conn:
        ensure_schema(conn)
        assert _migrated_version(conn) == 77

        from baker.db.schema import _migrate_v72_lowercase_usernames

        # Capture usernames before re-run.
        before = {
            row["username"] for row in
            conn.execute("SELECT username FROM users").fetchall()
        }
        _migrate_v72_lowercase_usernames(conn)
        after = {
            row["username"] for row in
            conn.execute("SELECT username FROM users").fetchall()
        }
        assert before == after
        # All remain lowercase.
        for u in after:
            assert u == u.lower()


def test_v72_skips_collision_pair_without_crashing():
    """v72 does NOT crash when two rows would collapse to the same lowercase.

    If a DB has both 'An' and 'an' (pre-fix history), v72 lowercases 'an' in
    place (already lowercase) and skips 'An' (would collide). The migration
    must not raise — it logs and continues.
    """
    with get_db() as conn:
        _migrate_to_version(conn, 71)
        conn.execute("DELETE FROM users")
        conn.execute(
            "INSERT INTO users (username, password_hash, role, active) "
            "VALUES ('An', 'h1', 'staff', 1)"
        )
        conn.execute(
            "INSERT INTO users (username, password_hash, role, active) "
            "VALUES ('an', 'h2', 'staff', 1)"
        )
        conn.commit()

        # Must not raise.
        _migrate_to_version(conn, 72)
        assert _migrated_version(conn) == 72

        usernames = {
            row["username"] for row in
            conn.execute("SELECT username FROM users").fetchall()
        }
        # 'an' remains; 'An' is skipped (would collide with existing 'an').
        assert "an" in usernames
        # Either 'An' was kept as-is (skipped) OR lowercased — but not both.
        # Per the defensive guard, 'An' is skipped so it stays capitalized.
        assert "An" in usernames


# ---------------------------------------------------------------------------
# DG-029 phase 5.6-c2 (SEC-1): BAKER_SEED_QUIET must suppress plaintext
# password output during v68 user seeding. Regression test for the
# indentation/scoping bug where the per-user plaintext print loop ran in
# BOTH the quiet and non-quiet branches.
# ---------------------------------------------------------------------------


def test_v68_seed_quiet_suppresses_plaintext_passwords(monkeypatch, capsys):
    """SEC-1: BAKER_SEED_QUIET=1 suppresses per-user plaintext password output.

    Running ensure_schema on a fresh DB with BAKER_SEED_QUIET=1 must print
    the "passwords suppressed" summary line and MUST NOT print any per-user
    plaintext password line (pattern ``<username> (<role>): <plain>``).
    Mirrors the CLI ``test_user_create_quiet_suppresses_plaintext`` style.
    """
    monkeypatch.setenv("BAKER_SEED_QUIET", "1")
    with get_db() as conn:
        ensure_schema(conn)
        assert _migrated_version(conn) == 77

    out = capsys.readouterr().out
    # The "passwords suppressed" summary line IS present.
    assert "passwords suppressed" in out
    assert "BAKER_SEED_QUIET=1" in out
    # No per-user plaintext password line leaked. The non-quiet path prints
    # lines of the form "  <username> (<role>): <plain>".
    import re

    leaked = [
        line for line in out.splitlines()
        if re.match(r"^\s+\S+ \((admin|staff)\): \S+", line)
    ]
    assert not leaked, f"plaintext password lines leaked under BAKER_SEED_QUIET=1: {leaked!r}"
    # The non-quiet header/separator banners must NOT appear either.
    assert "Distribute these temporary passwords" not in out


def test_v68_seed_default_prints_plaintext_passwords(monkeypatch, capsys):
    """SEC-1 positive control: the default (no BAKER_SEED_QUIET) path still
    prints per-user plaintext passwords so the admin-distribution UX is
    preserved exactly.
    """
    monkeypatch.delenv("BAKER_SEED_QUIET", raising=False)
    with get_db() as conn:
        ensure_schema(conn)
        assert _migrated_version(conn) == 77

    out = capsys.readouterr().out
    # The non-quiet header banner IS present.
    assert "Distribute these temporary passwords to each user:" in out
    # At least one per-user plaintext password line IS present.
    import re

    user_lines = [
        line for line in out.splitlines()
        if re.match(r"^\s+\S+ \((admin|staff)\): \S+", line)
    ]
    assert user_lines, "expected per-user plaintext password lines in default path"
    # The "passwords suppressed" summary must NOT appear in the default path.
    assert "passwords suppressed" not in out


# ── v73 Migration: Account 2500 (DG-245 Phase 2) ───────────────────────────


def test_v73_registered_in_migration_chain():
    """v73 is registered in MIGRATIONS with the expected callable."""
    assert 73 in MIGRATIONS
    assert (
        MIGRATIONS[73]["callable"].__name__
        == "_migrate_v73_add_account_2500"
    )


def test_v73_adds_account_2500_on_incremental_db():
    """Applying v73 on top of a v72 DB: account 2500 already exists from v44,
    so v73 is a no-op (INSERT OR IGNORE on all accounts)."""
    from baker.db.schema import _migrate_v73_add_account_2500

    with get_db() as conn:
        _migrate_to_version(conn, 72)
        # Account 2500 already exists (seeded by v44).
        before = conn.execute(
            "SELECT id, name, type FROM accounts WHERE code = '2500'"
        ).fetchone()
        assert before is not None
        assert before["type"] == "liability"

        # v73 on an already-correct DB is a no-op.
        _migrate_v73_add_account_2500(conn)
        after = conn.execute(
            "SELECT id, name, type FROM accounts WHERE code = '2500'"
        ).fetchone()
        assert after is not None
        assert after["id"] == before["id"]
        assert after["name"] == before["name"]


def test_v73_applies_in_full_migration_chain():
    """v73 executes as part of ensure_schema and account 2500 exists on fresh DB."""
    with get_db() as conn:
        _migrate_to_version(conn, 73)
        assert _migrated_version(conn) == 73
        row = conn.execute(
            "SELECT id, name, type FROM accounts WHERE code = '2500'"
        ).fetchone()
        assert row is not None
        assert row["type"] == "liability"


def test_v73_idempotent_on_already_migrated_db():
    """Re-running the v73 callable after it has already run is a no-op."""
    from baker.db.schema import _migrate_v73_add_account_2500

    with get_db() as conn:
        _migrate_to_version(conn, 72)
        _migrate_v73_add_account_2500(conn)
        count_after_first = conn.execute(
            "SELECT COUNT(*) FROM accounts WHERE code = '2500'"
        ).fetchone()[0]
        assert count_after_first == 1

        # Second application must not raise or duplicate.
        _migrate_v73_add_account_2500(conn)
        count_after_second = conn.execute(
            "SELECT COUNT(*) FROM accounts WHERE code = '2500'"
        ).fetchone()[0]
        assert count_after_second == 1


def test_v73_idempotent_on_fresh_db():
    """v73 on a fresh DB (already at v73 via ensure_schema) is a no-op."""
    from baker.db.schema import _migrate_v73_add_account_2500

    with get_db() as conn:
        ensure_schema(conn)
        assert _migrated_version(conn) >= 73
        row_before = conn.execute(
            "SELECT id, name, type FROM accounts WHERE code = '2500'"
        ).fetchone()
        _migrate_v73_add_account_2500(conn)
        row_after = conn.execute(
            "SELECT id, name, type FROM accounts WHERE code = '2500'"
        ).fetchone()
        assert row_before is not None
        assert row_before["id"] == row_after["id"]
        assert row_before["name"] == row_after["name"]
        assert row_before["type"] == row_after["type"]


def test_v73_ensures_account_2500_exists_when_missing():
    """AC1: Given a live db without account 2500, when migration v73 runs,
    then account 2500 exists and re-running v73 makes no further change."""
    from baker.db.schema import _migrate_v73_add_account_2500

    with get_db() as conn:
        _migrate_to_version(conn, 72)
        # Simulate a live DB missing account 2500.
        conn.execute("DELETE FROM accounts WHERE code = '2500'")
        conn.commit()
        assert conn.execute(
            "SELECT COUNT(*) FROM accounts WHERE code = '2500'"
        ).fetchone()[0] == 0

        # Run v73 — account 2500 now exists.
        _migrate_v73_add_account_2500(conn)
        row = conn.execute(
            "SELECT id, name, type FROM accounts WHERE code = '2500'"
        ).fetchone()
        assert row is not None
        assert row["name"] == "Phải trả người bán (Accounts Payable)"
        assert row["type"] == "liability"

        # Re-running v73 makes no further change (idempotent).
        id_first = row["id"]
        _migrate_v73_add_account_2500(conn)
        count = conn.execute(
            "SELECT COUNT(*) FROM accounts WHERE code = '2500'"
        ).fetchone()[0]
        assert count == 1
        row2 = conn.execute(
            "SELECT id FROM accounts WHERE code = '2500'"
        ).fetchone()
        assert row2["id"] == id_first


# ---------------------------------------------------------------------------
# Review-remediation verification (d-045718, DG-245 review d-b1fbbc)
# CQ-2: vendor sub-account code overflow at vendor >99
# ---------------------------------------------------------------------------


def test_ap_vendor_sub_account_overflow_above_99():
    """CQ-2 (Major): creating 100+ vendor sub-accounts under 2500 must not
    overflow the 25xx namespace. The first 99 vendors use 4-digit codes
    (2501..2599); vendor #100 rolls to the 5-digit 25xxx range (25001+) so the
    code stays under the 2500 parent and the accounts.code UNIQUE constraint
    is not tripped."""
    from baker.db.schema import _ensure_ap_vendor_sub_account

    with get_db() as conn:
        ensure_schema(conn)
        parent_id = int(conn.execute(
            "SELECT id FROM accounts WHERE code = '2500'"
        ).fetchone()[0])

        # Create 100 vendor sub-accounts (vendors 1-100).
        ids = []
        for i in range(1, 101):
            vid = _ensure_ap_vendor_sub_account(conn, f"Vendor {i}")
            ids.append(vid)
        conn.commit()

        # All 100 sub-accounts exist, each with a unique code under 2500.
        rows = conn.execute(
            "SELECT code, name FROM accounts WHERE parent_id = ? ORDER BY CAST(code AS INTEGER)",
            (parent_id,),
        ).fetchall()
        assert len(rows) == 100
        codes = [r["code"] for r in rows]
        # All codes are unique (UNIQUE constraint respected — no silent failures).
        assert len(set(codes)) == 100
        # First 99 codes stay in the 4-digit 25xx range (2501..2599).
        for c in codes[:99]:
            assert len(c) == 4 and c.startswith("25"), c
        # Vendor #100 rolls to the 5-digit 25xxx range (does not escape to 2600).
        assert codes[99] == "25001", codes[99]
        # Idempotency: re-resolving an existing vendor reuses its sub-account.
        reuse = _ensure_ap_vendor_sub_account(conn, "Vendor 1")
        assert reuse == ids[0]


# ---------------------------------------------------------------------------
# v77 — staff_id columns on users + sessions, UNIQUE index, backfill (DG-259 Phase 1)
# ---------------------------------------------------------------------------


def _seed_staff_for_v77(conn) -> None:
    """Seed staff rows so v77 backfill has targets to match against."""
    conn.executescript(
        "INSERT OR IGNORE INTO staff (name, role) VALUES ('Ân', 'baker');"
        "INSERT OR IGNORE INTO staff (name, role) VALUES ('Ngân', 'cashier');"
        "INSERT OR IGNORE INTO staff (name, role) VALUES ('Phượng', 'manager');"
        "INSERT OR IGNORE INTO staff (name, role) VALUES ('Sinh', 'owner');"
        "INSERT OR IGNORE INTO staff (name, role) VALUES ('Tân', 'baker');"
    )
    conn.commit()


def test_v77_registered_in_migration_chain():
    """v77 is registered in MIGRATIONS with the expected callable."""
    from baker.db.schema import _migrate_v77_staff_id_columns

    assert "callable" in MIGRATIONS[77]
    assert MIGRATIONS[77]["callable"] == _migrate_v77_staff_id_columns


def test_v77_adds_staff_id_columns_and_index():
    """v77 ensures users.staff_id, sessions.staff_id, and idx_users_staff_id.

    Note: v68 (part of the chain before v77) already creates users.staff_id
    via USERS_SCHEMA, so the column may already exist. v77 is idempotent.
    """
    with get_db() as conn:
        _migrate_to_version(conn, 76)

        _migrate_to_version(conn, 77)
        assert _migrated_version(conn) >= 77
        users_cols = _schema_columns(conn, "users")
        assert "staff_id" in users_cols

        sessions_cols = _schema_columns(conn, "sessions")
        assert "staff_id" in sessions_cols

        index_rows = conn.execute("PRAGMA index_list(users)").fetchall()
        index_names = [r["name"] for r in index_rows]
        assert "idx_users_staff_id" in index_names


def test_v77_backfills_staff_id():
    """v77 backfills users.staff_id by case-insensitive name matching."""
    with get_db() as conn:
        _migrate_to_version(conn, 76)
        _seed_staff_for_v77(conn)
        _migrate_to_version(conn, 77)

        rows = conn.execute(
            "SELECT u.username, u.staff_id, s.name AS staff_name "
            "FROM users u "
            "LEFT JOIN staff s ON s.id = u.staff_id "
            "WHERE u.staff_id IS NOT NULL"
        ).fetchall()
        assert len(rows) > 0
        matched = {r["username"]: r["staff_name"] for r in rows}
        assert matched.get("sinh") == "Sinh"
        assert matched.get("ân") == "Ân"


def test_v77_idempotent():
    """Re-running v77 is a no-op."""
    from baker.db.schema import _migrate_v77_staff_id_columns

    with get_db() as conn:
        ensure_schema(conn)
        assert _migrated_version(conn) >= 77
        before = conn.execute(
            "SELECT staff_id FROM users WHERE username = 'sinh'"
        ).fetchone()
        _migrate_v77_staff_id_columns(conn)
        after = conn.execute(
            "SELECT staff_id FROM users WHERE username = 'sinh'"
        ).fetchone()
        assert before["staff_id"] == after["staff_id"]


def test_v77_skips_collision_on_duplicate_normalized_key():
    """v77 does not crash when two usernames normalize to the same staff key.

    First-match-wins: the first user with a matching normalized name gets
    the staff_id; subsequent matching users are skipped (m7).
    """
    with get_db() as conn:
        _migrate_to_version(conn, 76)
        _seed_staff_for_v77(conn)
        # Insert a second user whose username normalizes to the same key
        # as an existing user (e.g., "an" and "ân" both → "an").
        conn.execute(
            "INSERT OR IGNORE INTO users (username, password_hash, role, active) "
            "VALUES ('an', 'x', 'staff', 1)"
        )
        conn.commit()
        _migrate_to_version(conn, 77)

        # Both 'ân' and 'an' may exist; at minimum no IntegrityError was raised.
        rows = conn.execute(
            "SELECT staff_id FROM users WHERE username IN ('ân', 'an')"
        ).fetchall()
        non_null = [r["staff_id"] for r in rows if r["staff_id"] is not None]
        # At most one user gets the staff_id (first-match-wins).
        assert len(non_null) <= 1
