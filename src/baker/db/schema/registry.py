"""MIGRATIONS registry and ensure_schema entry point (extracted from schema.py)."""


from ._constants import *  # noqa: F401,F403
from ._helpers import *  # noqa: F401,F403

from .migrations.v004 import _migrate_v4_assign_codes
from .migrations.v005 import _migrate_v5_update_categories
from .migrations.v006 import _migrate_v6_seed_variants
from .migrations.v008 import _migrate_v8_photos
from .migrations.v012 import _migrate_v12_data
from .migrations.v014 import _migrate_v14_seed_order_sources
from .migrations.v016 import _migrate_v16_staff_and_created_by
from .migrations.v017 import _migrate_v17_fix_staff_names
from .migrations.v018 import _migrate_v18_seed_checklist
from .migrations.v020 import _migrate_v20_seed_shipping_and_extras
from .migrations.v023 import _migrate_v23_product_attributes
from .migrations.v024 import _migrate_v24_rut_tien_toggle
from .migrations.v025 import _migrate_v25_tien_rut_rename
from .migrations.v026 import _migrate_v26_trung_bay_and_stock
from .migrations.v027 import _migrate_v27_seed_catalog_tags
from .migrations.v028 import _migrate_v28_cascade_and_reseed
from .migrations.v029 import _migrate_v29_add_pin_support
from .migrations.v031 import _migrate_v31_enum_attributes
from .migrations.v032 import _migrate_v32_print_tracking
from .migrations.v035 import _migrate_v35_reconciliation_line_waste_reason
from .migrations.v036 import _migrate_v36_chip_aware_inventory
from .migrations.v037 import _migrate_v37_price_bucket_consolidation
from .migrations.v038 import _migrate_v38_accessory_products
from .migrations.v042 import _migrate_v42_backfill_payment_source
from .migrations.v043 import _migrate_v43_event_history_and_soft_delete
from .migrations.v044 import _migrate_v44_double_entry_accounting
from .migrations.v045 import _migrate_v45_cost_history_and_cost_at_sale
from .migrations.v046 import _migrate_v46_fix_old_expense_journal
from .migrations.v047 import _migrate_v47_fix_stale_cogs_entries
from .migrations.v048 import _migrate_v48_fix_inventory_purchase_entries
from .migrations.v049 import _migrate_v49_bus_shipping_backfill
from .migrations.v050 import _migrate_v50_journal_transaction_date
from .migrations.v051 import _migrate_v51_backfill_journal_transaction_date
from .migrations.v052 import _migrate_v52_reclassify_staff_advances_as_liabilities
from .migrations.v053 import _migrate_v53_payment_transaction_invalidation
from .migrations.v054 import _migrate_v54_add_account_2400
from .migrations.v055 import _migrate_v55_utc_timestamp_standardization
from .migrations.v056 import _migrate_v56_customers_and_order_link
from .migrations.v057 import _migrate_v57_generate_customers_from_orders
from .migrations.v058 import _migrate_v58_customer_phones
from .migrations.v059 import _migrate_v59_deduplicate_customers
from .migrations.v060 import _migrate_v60_customer_year_summary
from .migrations.v061 import _migrate_v61_customer_search_name
from .migrations.v062 import _migrate_v62_negative_balance
from .migrations.v063 import _migrate_v63_repair_zero_cogs_and_missing_entries
from .migrations.v064 import _migrate_v64_delivery_phone
from .migrations.v065 import _migrate_v65_journal_sync_failure_log
from .migrations.v066 import _migrate_v66_repair_customer_links
from .migrations.v068 import _migrate_v68_users_table
from .migrations.v071 import _migrate_v71_users_role_check
from .migrations.v072 import _migrate_v72_lowercase_usernames
from .migrations.v073 import _migrate_v73_add_account_2500
from .migrations.v074 import _migrate_v74_backfill_null_customer_links
from .migrations.v075 import _migrate_v75_backfill_primary_customer_phones
from .migrations.v076 import _migrate_v76_add_transaction_bank_sub_accounts
from .migrations.v077 import _migrate_v77_staff_id_columns
from .migrations.v078 import _migrate_v78_add_staff_name_to_events
from .migrations.v079 import _migrate_v79_add_staff_name_to_orders
from .migrations.v080 import _migrate_v80_drop_amount_paid_from_orders
from .migrations.v082 import _migrate_v82_add_blank_id_to_order_items
from .migrations.v083 import _migrate_v83_order_item_blanks
from .migrations.v084 import _migrate_v84_order_item_assigned_price
from .migrations.v085 import _migrate_v85_add_account_1600
from .migrations.v086 import _migrate_v86_expense_categories
from .migrations.v087 import _migrate_v87_order_delivery_schedule_gps
from .migrations.v089 import _migrate_v89_order_assigned_staff_id
from .migrations.v090 import _migrate_v90_force_password_change
from .migrations.v091 import _migrate_v91_cash_drawer_schema
from .migrations.v092 import _migrate_v92_cash_drawer_sub_accounts
from .migrations.v093 import _migrate_v93_rename_quy_to_quay_in_journal_entries
from .migrations.v094 import _migrate_v94_cash_drawer_tien_rut_columns
from .migrations.v095 import _migrate_v95_cash_drawer_journal_balance
from .migrations.v096 import _migrate_v96_cash_drawer_counted_opening_balance
from .migrations.v097 import _migrate_v97_cash_drawer_breakdown_snapshot
from .migrations.v098 import _migrate_v98_reconciliation_sale_rows_linked_order_refs
from .migrations.v099 import _migrate_v99_cash_drawer_reconciled_column

MIGRATIONS = {
    1: {
        "description": "Initial schema",
        "sql": INITIAL_SCHEMA,
    },
    2: {
        "description": "Staff tracking and event people",
        "sql": "ALTER TABLE events ADD COLUMN logged_by TEXT DEFAULT '';\n"
               + STAFF_AND_PEOPLE_SCHEMA,
    },
    3: {
        "description": "Product photo_path column and seed 23 products",
        "sql": PHOTO_PATH_AND_SEED,
        "seed": SEED_PRODUCTS,
    },
    4: {
        "description": "Product codes and categories table",
        "sql": PRODUCT_CODE_AND_CATEGORIES_SCHEMA,
        "callable": _migrate_v4_assign_codes,
    },
    5: {
        "description": "Update product categories to new slugs",
        "sql": "",
        "callable": _migrate_v5_update_categories,
    },
    6: {
        "description": "Seed cake variants (16/18/20/22cm × thường/cao/tầng) and su kem sets",
        "sql": "",
        "callable": _migrate_v6_seed_variants,
    },
    7: {
        "description": "Product catalog photos table for gallery feature",
        "sql": PRODUCT_CATALOG_PHOTOS_SCHEMA,
    },
    8: {
        "description": "Photos table (flat hash storage), categories icon+position, product FK",
        "sql": PHOTOS_TABLE_AND_PHOTO_IDS_SCHEMA,
        "callable": _migrate_v8_photos,
    },
    9: {
        "description": "Rename event type 'incident' to 'equipment'",
        "sql": "UPDATE events SET type = 'equipment' WHERE type = 'incident';",
    },
    10: {
        "description": "Add amount_paid to orders table",
        "sql": "ALTER TABLE orders ADD COLUMN amount_paid REAL DEFAULT 0;",
    },
    11: {
        "description": "Order photos table for decoration references and chat screenshots",
        "sql": ORDER_PHOTOS_SCHEMA,
    },
    12: {
        "description": "order_items and payment_transactions tables with data migration",
        "sql": ORDER_ITEMS_AND_PAYMENT_TRANSACTIONS_SCHEMA,
        "callable": _migrate_v12_data,
    },
    13: {
        "description": "Per-item birthday/age fields and order_photos work_item_id FK",
        "sql": PER_ITEM_BIRTHDAY_AND_PHOTO_LINK_SCHEMA,
    },
    14: {
        "description": "app_config table for general config (order sources etc), source column on orders",
        "sql": APP_CONFIG_AND_ORDER_SOURCE_SCHEMA,
        "callable": _migrate_v14_seed_order_sources,
    },
    15: {
        "description": "Server logs and log triggers tables for API logging system",
        "sql": SERVER_LOGS_AND_TRIGGERS_SCHEMA,
    },
    16: {
        "description": "Seed staff table (5 members) and add created_by column to orders",
        "sql": "",
        "callable": _migrate_v16_staff_and_created_by,
    },
    17: {
        "description": "Fix staff names to use Vietnamese diacritics",
        "sql": "",
        "callable": _migrate_v17_fix_staff_names,
    },
    18: {
        "description": "Checklist templates and entries tables with seed data",
        "sql": CHECKLIST_SCHEMA,
        "callable": _migrate_v18_seed_checklist,
    },
    19: {
        "description": "Order history audit table for tracking all order changes",
        "sql": ORDER_HISTORY_SCHEMA,
    },
    20: {
        "description": "Add shipping_fee to orders, is_extra and is_gift to order_items, seed shipping presets and extras",
        "sql": SHIPPING_FEE_AND_EXTRAS_SCHEMA,
        "callable": _migrate_v20_seed_shipping_and_extras,
    },
    21: {
        "description": "Add work_ticket_printed_at column to orders for tracking work ticket print state",
        "sql": WORK_TICKET_PRINTED_AT_SCHEMA,
    },
    22: {
        "description": "Knowledge base: knowledge_entries and knowledge_entry_photos tables",
        "sql": KNOWLEDGE_BASE_SCHEMA,
    },
    23: {
        "description": "Product attribute system: product_attributes table, product_attribute_values table, order_items.attributes column, seed cash_amount and cash_fee for banh_kem",
        "sql": PRODUCT_ATTRIBUTES_SCHEMA + ORDER_ITEMS_ATTRIBUTES_SCHEMA,
        "callable": _migrate_v23_product_attributes,
    },
    24: {
        "description": "Add rut_tien per-product toggle: rut_tien attribute type, seed all existing banh_kem products with rut_tien=true",
        "sql": "",
        "callable": _migrate_v24_rut_tien_toggle,
    },
    25: {
        "description": "Rename rut_tien transaction type to tien_rut in payment_transactions for Vietnamese term consistency",
        "sql": "",
        "callable": _migrate_v25_tien_rut_rename,
    },
    26: {
        "description": "Add trung_bay and tang_kem product attributes; create product_stock and stock_movements tables for inventory management",
        "sql": PRODUCT_STOCK_SCHEMA,
        "callable": _migrate_v26_trung_bay_and_stock,
    },
    27: {
        "description": "Create catalog_photo_tags junction table and seed 20 catalog tag entries into app_config",
        "sql": CATALOG_PHOTO_TAGS_SCHEMA,
        "callable": _migrate_v27_seed_catalog_tags,
    },
    28: {
        "description": "Rebuild catalog_photo_tags with ON DELETE CASCADE; re-seed catalog_tag vocabulary with approved F1 keys (fixes v27 typos and wrong keys)",
        "sql": "",
        "callable": _migrate_v28_cascade_and_reseed,
    },
    29: {
        "description": "Add pin support to knowledge entries",
        "sql": "",
        "callable": _migrate_v29_add_pin_support,
    },
    30: {
        "description": "Add product price chips table for preset pricing",
        "sql": PRODUCT_PRICE_CHIPS_SCHEMA,
    },
    31: {
        "description": "Enum product attributes: product_attribute_options table; seed nhan_banh attribute with 5 fillings for banh_kem (Sầu riêng default)",
        "sql": PRODUCT_ATTRIBUTE_OPTIONS_SCHEMA,
        "callable": _migrate_v31_enum_attributes,
    },
    32: {
        "description": "Print tracking: print_log table and work_ticket_printed_by column",
        "sql": PRINT_LOG_AND_PRINTED_BY_SCHEMA,
        "callable": _migrate_v32_print_tracking,
    },
    33: {
        "description": "Reconciliation sessions and line history tables",
        "sql": RECONCILIATIONS_SCHEMA,
    },
    34: {
        "description": "Grouped reconciliation sale rows table",
        "sql": RECONCILIATION_SALE_ROWS_SCHEMA,
    },
    35: {
        "description": "Add per-line waste reason to reconciliation lines",
        "sql": "",
        "callable": _migrate_v35_reconciliation_line_waste_reason,
    },
    36: {
        "description": "Chip-aware inventory schema: stock_lots, inventory_items, option columns, and product_stock migration",
        "sql": STOCK_LOTS_AND_ITEMS_SCHEMA,
        "callable": _migrate_v36_chip_aware_inventory,
    },
    37: {
        "description": "Consolidate stock lots by normalized selling price buckets",
        "sql": "",
        "callable": _migrate_v37_price_bucket_consolidation,
    },
    38: {
        "description": "Migrate order_extra app config rows into product-backed phu_kien accessories",
        "sql": "",
        "callable": _migrate_v38_accessory_products,
    },
    39: {
        "description": "Add public order code column and per-due-date uniqueness index",
        "sql": PUBLIC_ORDER_CODE_SCHEMA,
    },
    40: {
        "description": "Add order_id nullable FK to events table for order incident linking",
        "sql": ORDER_INCIDENT_ORDER_ID_SCHEMA,
    },
    41: {
        "description": "Create event_photos junction table linking events to photo attachments",
        "sql": EVENT_PHOTOS_SCHEMA,
    },
    42: {
        "description": "Backfill payment_source for existing expense events",
        "sql": "",
        "callable": _migrate_v42_backfill_payment_source,
    },
    43: {
        "description": "Event history audit table, soft-delete columns on events, backfill expense staff_name to audit log",
        "sql": "",
        "callable": _migrate_v43_event_history_and_soft_delete,
    },
    44: {
        "description": "Double-entry accounting: accounts, journal_entries, journal_lines, chart of accounts seed, backfill historical entries",
        "sql": "",
        "callable": _migrate_v44_double_entry_accounting,
    },
    45: {
        "description": "Cost data foundation: cost_history table, order_items.cost_at_sale column, backfill delivered order_items with baseline costs",
        "sql": "",
         "callable": _migrate_v45_cost_history_and_cost_at_sale,
     },
     46: {
         "description": "One-time fix: backfill journal entry for old-format expense event #25 (pre-standardization data)",
         "sql": "",
         "callable": _migrate_v46_fix_old_expense_journal,
     },
     47: {
         "description": "One-time fix: delete and re-create stale order_cogs entries generated with old cost resolver (no baseline fallback)",
         "sql": "",
         "callable": _migrate_v47_fix_stale_cogs_entries,
     },
     48: {
         "description": "One-time fix: re-route Nguyên liệu and Bao bì expense journal entries to debit Inventory (1300) instead of expense accounts",
         "sql": "",
         "callable": _migrate_v48_fix_inventory_purchase_entries,
     },
     49: {
         "description": "Bus shipping accounting backfill: fix revenue entries, create hold+release entries for delivered bus orders",
         "sql": "",
         "callable": _migrate_v49_bus_shipping_backfill,
     },
     50: {
         "description": "Add transaction_date column + index to journal_entries (DG-192 Phase 4.1)",
         "sql": "",
         "callable": _migrate_v50_journal_transaction_date,
     },
    51: {
        "description": "Re-backfill journal_entries.transaction_date from source record dates (DG-192 Phase 4.1)",
        "sql": "",
        "callable": _migrate_v51_backfill_journal_transaction_date,
    },
    52: {
        "description": "Reclassify staff advance accounts (1400 asset) to staff payables (2300 liability) — DG-194 review remediation",
        "sql": "",
        "callable": _migrate_v52_reclassify_staff_advances_as_liabilities,
    },
     53: {
         "description": "Add invalidated_at/invalidated_by soft-delete columns to payment_transactions — DG-196 payment transaction invalidation",
         "sql": "",
         "callable": _migrate_v53_payment_transaction_invalidation,
     },
     54: {
         "description": "Ensure account 2400 (Tien Rut Held) exists in chart of accounts — DG-199 Phase 4.2",
         "sql": "",
         "callable": _migrate_v54_add_account_2400,
     },
     55: {
         "description": "UTC timestamp standardization — append Z to bare timestamps, convert +07:00 to UTC Z (DG-202 Phase 2)",
         "sql": "",
         "callable": _migrate_v55_utc_timestamp_standardization,
     },
    56: {
        "description": "Customer management foundation: customers table, customer_id FK on orders, auto-match existing orders by phone (DG-182 Phase 1)",
        "sql": CUSTOMERS_SCHEMA,
        "callable": _migrate_v56_customers_and_order_link,
    },
    57: {
        "description": "Generate customer records from existing orders and link orders to them — earliest-order-wins for shared phones, idempotent re-run (DG-204 Phase 2)",
        "sql": "",
        "callable": _migrate_v57_generate_customers_from_orders,
    },
    58: {
        "description": "Customer multi-phone: customer_phones table + migrate existing customers.phone as primary phone, idempotent re-run (DG-205 Phase 1)",
        "sql": CUSTOMER_PHONES_SCHEMA,
        "callable": _migrate_v58_customer_phones,
    },
    59: {
        "description": "Deduplicate customers with same case-insensitive name — merge orders, keep most-active, delete dupes (DG-205 follow-up)",
        "sql": "",
        "callable": _migrate_v59_deduplicate_customers,
    },
    60: {
        "description": "Customer yearly summary table (customer_year_summary) for order count + total volume per year, backfill from existing orders (DG-206 Phase 1)",
        "sql": CUSTOMER_YEAR_SUMMARY_SCHEMA,
        "callable": _migrate_v60_customer_year_summary,
    },
    61: {
        "description": "Add search_name column to customers for diacritic-insensitive search, backfill from existing names (DG-206 follow-up)",
        "sql": "",
        "callable": _migrate_v61_customer_search_name,
    },
    62: {
        "description": "Negative inventory: negative_balance table tracking oversold qty per (product_id, price_chip_id) (DG-200 Phase 1)",
        "sql": "",
        "callable": _migrate_v62_negative_balance,
    },
    63: {
        "description": "Repair zero-cost order_items (unit_price anchor) and missing order_cogs journal entries — DG-208 Phase 2",
        "sql": "",
        "callable": _migrate_v63_repair_zero_cogs_and_missing_entries,
    },
    64: {
        "description": "Add delivery_phone column to orders table — DG-211 Phase 4.1",
        "sql": "",
        "callable": _migrate_v64_delivery_phone,
    },
    65: {
        "description": "Create journal_sync_failure_log table for per-source audit records — DG-226 Phase 1",
        "sql": "",
        "callable": _migrate_v65_journal_sync_failure_log,
    },
    66: {
        "description": "Repair unlinked orders — link all NULL customer_id orders by phone/name/walk-in, idempotent re-run (DG-227 Phase 2)",
        "sql": "",
        "callable": _migrate_v66_repair_customer_links,
    },
    67: {
        "description": "Add acknowledged_at column to orders for order acknowledgment tracking — DG-221 Phase 1",
        "sql": "ALTER TABLE orders ADD COLUMN acknowledged_at TEXT DEFAULT NULL;",
    },
    68: {
        "description": "Auth RBAC: users table for JWT authentication + seed existing staff as users — DG-029 Phase 1",
        "sql": USERS_SCHEMA,
        "callable": _migrate_v68_users_table,
    },
    69: {
        "description": "Auth RBAC: audit_log table for recording admin write operations — DG-029 Phase 3",
        "sql": AUDIT_LOG_SCHEMA,
    },
    70: {
        "description": "Auth RBAC: sessions table for active session tracking — DG-029 Phase 4",
        "sql": SESSIONS_SCHEMA,
    },
    71: {
        "description": "Auth RBAC: DB-level CHECK(role IN ('admin','staff')) on users table — DG-029 phase 5.6-c1 (Mn-3)",
        # No-op SQL block; the callable does the conditional rebuild. On
        # fresh DBs USERS_SCHEMA (with the CHECK) is applied by v68's
        # `CREATE TABLE IF NOT EXISTS`, which is a no-op if the table
        # already exists, so this migration's callable is the authority.
        "sql": "",
        "callable": _migrate_v71_users_role_check,
    },
    72: {
        "description": "Auth RBAC: lowercase existing users.username values — DG-029 follow-on",
        "sql": "",
        "callable": _migrate_v72_lowercase_usernames,
    },
    73: {
        "description": "Chart of accounts: ensure account 2500 (Accounts Payable) exists — DG-245 Phase 2",
        "sql": "",
        "callable": _migrate_v73_add_account_2500,
    },
    74: {
        "description": "Backfill remaining NULL customer_id orders (phone → name → new customer → 'Khách lẻ'), idempotent re-run with pre/post counts — DG-252 Phase 4",
        "sql": "",
        "callable": _migrate_v74_backfill_null_customer_links,
    },
    75: {
        "description": "Backfill a primary customer_phones row from non-empty customers.phone for all customers with zero phone rows (DG-252 r4 [MAJOR] data-loss defense)",
        "sql": "",
        "callable": _migrate_v75_backfill_primary_customer_phones,
    },
    76: {
        "description": "Chart of accounts: ensure bank sub-accounts 1210 (Phượng VCB), 1220 (Ân VCB), 1290 (un-allocated) exist — DG-244 Phase 4",
        "sql": "",
        "callable": _migrate_v76_add_transaction_bank_sub_accounts,
    },
    77: {
        "description": "Add staff_id columns to users and sessions tables, create UNIQUE index, back-link existing users to staff — DG-259 Phase 1",
        "sql": "",
        "callable": _migrate_v77_staff_id_columns,
    },
    78: {
        "description": "Add staff_name column to events table for display-name attribution — DG-259 Cycle 4",
        "sql": "",
        "callable": _migrate_v78_add_staff_name_to_events,
    },
    79: {
        "description": "Add created_staff_name and work_ticket_printed_staff_name to orders table for display-name attribution — DG-259 Cycle 5",
        "sql": "",
        "callable": _migrate_v79_add_staff_name_to_orders,
    },
    80: {
        "description": "Drop redundant amount_paid column from orders table — live-computed from payment_transactions (DG-274)",
        "sql": "",
        "callable": _migrate_v80_drop_amount_paid_from_orders,
    },
    81: {
        "description": "Blanks foundation: blanks, product_blank_bom, blank_stock, blank_stock_log tables (DG-290 Phase 4.1)",
        "sql": BLANKS_SCHEMA,
    },
    82: {
        "description": "Add blank_id nullable FK column to order_items + index (DG-293 Phase 1)",
        "sql": "",
        "callable": _migrate_v82_add_blank_id_to_order_items,
    },
    83: {
        "description": "Replace order_items.blank_id with order_item_blanks junction table (DG-294 Phase 1)",
        "sql": "",
        "callable": _migrate_v83_order_item_blanks,
    },
    84: {
        "description": "Add assigned_price REAL DEFAULT NULL column to order_items for trưng bày markup audit (DG-296 Phase 1)",
        "sql": "",
        "callable": _migrate_v84_order_item_assigned_price,
    },
    85: {
        "description": "Seed account 1600 (Tài sản cố định / Fixed Assets) for investing-activity cash flows (DG-300 Phase 1)",
        "sql": "",
        "callable": _migrate_v85_add_account_1600,
    },
    86: {
        "description": "Expense subcategories: expense_categories table + seed data + account codes 5110-5140, 5210-5230 (DG-302 Phase 1)",
        "sql": "",
        "callable": _migrate_v86_expense_categories,
    },
    87: {
        "description": "Add latitude, longitude, google_maps_url, delivery_time_slot nullable columns to orders for door delivery schedule + GPS (DG-303 Phase 4.1)",
        "sql": "",
        "callable": _migrate_v87_order_delivery_schedule_gps,
    },
    88: {
        "description": "Add composite indexes on orders(status, due_date) and orders(customer_id, created_at) for common query patterns (DG-308 Phase 4.4)",
        "sql": (
            "CREATE INDEX IF NOT EXISTS idx_orders_status_due_date "
            "ON orders(status, due_date);\n"
            "CREATE INDEX IF NOT EXISTS idx_orders_customer_id_created_at "
            "ON orders(customer_id, created_at);"
        ),
    },
    89: {
        "description": "Add assigned_staff_id nullable column to orders for delivery staff claiming (DG-310 Phase 3)",
        "sql": "",
        "callable": _migrate_v89_order_assigned_staff_id,
    },
    90: {
        "description": "Add force_password_change INTEGER NOT NULL DEFAULT 0 column to users table for self-service password change flow (DG-319 Phase 1)",
        "sql": "",
        "callable": _migrate_v90_force_password_change,
    },
    91: {
        "description": "Create cash_drawer table + add cash_drawer_id nullable FK columns to payment_transactions and events (DG-324 Phase 1)",
        "sql": "",
        "callable": _migrate_v91_cash_drawer_schema,
    },
    92: {
        "description": "Insert cash drawer sub-accounts 1101/1102 and transfer existing 1100 balance to 1101 (DG-330 Phase 2)",
        "sql": "",
        "callable": _migrate_v92_cash_drawer_sub_accounts,
    },
    93: {
        "description": "Rename 'quỹ' → 'quầy' in journal_entries.description for terminology consistency (DG-337 Phase 5)",
        "sql": "",
        "callable": _migrate_v93_rename_quy_to_quay_in_journal_entries,
    },
    94: {
        "description": "Add tien_rut_in/tien_rut_out INTEGER columns to cash_drawer for separate tien rut tracking (DG-341 Phase 4.1)",
        "sql": "",
        "callable": _migrate_v94_cash_drawer_tien_rut_columns,
    },
    95: {
        "description": "Refactor cash drawer balance to derive from journal: add closing_balance, create cash_drawer_journal_entries join table, drop accumulator columns, drop cash_drawer_id from payment_transactions/events (DG-347 Phase 1)",
        "sql": "",
        "callable": _migrate_v95_cash_drawer_journal_balance,
    },
    96: {
        "description": "Add counted_opening_balance INTEGER column to cash_drawer and backfill existing rows with counted_opening_balance = opening_balance (DG-354 Phase 1)",
        "sql": "",
        "callable": _migrate_v96_cash_drawer_counted_opening_balance,
    },
    97: {
        "description": "Create cash_drawer_breakdown_snapshot table + backfill snapshots for all already-closed drawers from linked 1101/2200 journal lines (DG-363 Phase 1)",
        "sql": "",
        "callable": _migrate_v97_cash_drawer_breakdown_snapshot,
    },
    98: {
        "description": "Add linked_order_refs TEXT column to reconciliation_sale_rows for 1-order-per-cake order list (DG-368 Phase 1)",
        "sql": "",
        "callable": _migrate_v98_reconciliation_sale_rows_linked_order_refs,
    },
    99: {
        "description": "Add reconciled INTEGER NOT NULL DEFAULT 0 column to cash_drawer for edit-lock on reconciled drawers (DG-379 Phase 4.1)",
        "sql": "",
        "callable": _migrate_v99_cash_drawer_reconciled_column,
    },
}

def ensure_schema(conn):
    """Apply any pending migrations."""
    cursor = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_version'"
    )
    if not cursor.fetchone():
        current_version = 0
    else:
        cursor = conn.execute("SELECT MAX(version) FROM schema_version")
        row = cursor.fetchone()
        current_version = row[0] if row[0] is not None else 0

    for version in sorted(MIGRATIONS.keys()):
        if version > current_version:
            conn.executescript(MIGRATIONS[version]["sql"])

            # Seed data if present
            seed = MIGRATIONS[version].get("seed")
            if seed:
                for name, category, base_price, cost, recipe_notes in seed:
                    conn.execute(
                        "INSERT OR IGNORE INTO products "
                        "(name, category, base_price, cost, recipe_notes) "
                        "VALUES (?, ?, ?, ?, ?)",
                        (name, category, base_price, cost, recipe_notes),
                    )

            # Run callable if present (for complex migrations)
            callable_fn = MIGRATIONS[version].get("callable")
            if callable_fn:
                callable_fn(conn)

            conn.execute(
                "INSERT INTO schema_version (version, description) VALUES (?, ?)",
                (version, MIGRATIONS[version]["description"]),
            )
    conn.commit()
