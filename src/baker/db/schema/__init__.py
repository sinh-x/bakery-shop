"""Backward-compatible barrel for ``baker.db.schema``.

Re-exports the full public surface of the original monolithic ``schema.py`` so
that every ``from baker.db.schema import ...`` continues to work unchanged.
The implementation is split across:
  - ``_constants``: schema strings, seed lists, account/code constants
  - ``_helpers``: shared helper functions used across migrations
  - ``migrations/vNNN``: one module per migration version
  - ``registry``: the MIGRATIONS dict and ensure_schema entry point
"""

from ._constants import (  # noqa: F401
    INITIAL_SCHEMA,
    STAFF_AND_PEOPLE_SCHEMA,
    PHOTO_PATH_AND_SEED,
    SEED_PRODUCTS,
    PRODUCT_CODE_AND_CATEGORIES_SCHEMA,
    SEED_CATEGORIES,
    _OLD_CATEGORY_TO_SLUG,
    SEED_CAKE_VARIANTS,
    SEED_SU_KEM_SETS,
    PRODUCT_CATALOG_PHOTOS_SCHEMA,
    PHOTOS_TABLE_AND_PHOTO_IDS_SCHEMA,
    ORDER_PHOTOS_SCHEMA,
    ORDER_ITEMS_AND_PAYMENT_TRANSACTIONS_SCHEMA,
    PER_ITEM_BIRTHDAY_AND_PHOTO_LINK_SCHEMA,
    APP_CONFIG_AND_ORDER_SOURCE_SCHEMA,
    SEED_ORDER_SOURCES,
    SERVER_LOGS_AND_TRIGGERS_SCHEMA,
    SEED_STAFF,
    CHECKLIST_SCHEMA,
    SEED_CHECKLIST_OPENING,
    SEED_CHECKLIST_CLOSING,
    ORDER_HISTORY_SCHEMA,
    SHIPPING_FEE_AND_EXTRAS_SCHEMA,
    SEED_SHIPPING_AND_EXTRAS,
    WORK_TICKET_PRINTED_AT_SCHEMA,
    PRINT_LOG_AND_PRINTED_BY_SCHEMA,
    RECONCILIATIONS_SCHEMA,
    RECONCILIATION_SALE_ROWS_SCHEMA,
    STOCK_LOTS_AND_ITEMS_SCHEMA,
    ORDER_INCIDENT_ORDER_ID_SCHEMA,
    EVENT_PHOTOS_SCHEMA,
    PUBLIC_ORDER_CODE_SCHEMA,
    PRODUCT_ATTRIBUTES_SCHEMA,
    ORDER_ITEMS_ATTRIBUTES_SCHEMA,
    SEED_PRODUCT_ATTRIBUTES,
    KNOWLEDGE_BASE_SCHEMA,
    CATALOG_PHOTO_TAGS_SCHEMA,
    SEED_CATALOG_TAGS,
    KNOWLEDGE_PIN_SCHEMA,
    ALLOWED_TABLES,
    PRODUCT_STOCK_SCHEMA,
    PRODUCT_PRICE_CHIPS_SCHEMA,
    PRODUCT_ATTRIBUTE_OPTIONS_SCHEMA,
    SEED_NHAN_BANH_OPTIONS,
    EVENT_HISTORY_AND_SOFT_DELETE_SCHEMA,
    ACCOUNTING_SCHEMA,
    EXPENSE_CATEGORIES_SCHEMA,
    SEED_EXPENSE_CATEGORIES,
    CASH_DRAWER_SCHEMA,
    CASH_DRAWER_JOURNAL_ENTRIES_SCHEMA,
    SEED_CHART_OF_ACCOUNTS,
    EXPENSE_CATEGORY_TO_ACCOUNT_CODE,
    INVENTORY_PURCHASE_CATEGORIES,
    EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE,
    PAYMENT_METHOD_TO_ASSET_CODE,
    TRANSACTION_PAYMENT_SOURCE_TO_ASSET_CODE,
    UNALLOCATED_BANK_CODE,
    EXPENSE_DEBT_PAYMENT_METHOD,
    ACCOUNTS_PAYABLE_CODE,
    PAYMENT_OUTFLOW_TYPES,
    PAYMENT_TIEN_RUT_TYPES,
    CUSTOMER_DEPOSITS_CODE,
    ORDER_REVENUE_CODE,
    COGS_CODE,
    PROMO_EXPENSE_CODE,
    INVENTORY_CODE,
    STAFF_PAYABLES_CODE,
    ACCOUNTS_RECEIVABLE_CODE,
    BUS_SHIPPING_HELD_CODE,
    TIEN_RUT_HELD_CODE,
    REVENUE_UPDATE_TOLERANCE,
    JOURNAL_SYNC_FAILURE_LOG_SCHEMA,
    NEGATIVE_BALANCE_SCHEMA,
    COST_HISTORY_SCHEMA,
    PHU_KIEN_CATEGORY,
    _TIMESTAMP_COLUMNS_V55,
    CUSTOMERS_SCHEMA,
    CUSTOMER_PHONES_SCHEMA,
    CUSTOMER_YEAR_SUMMARY_SCHEMA,
    USERS_SCHEMA,
    _SEED_STAFF_ROLE_TO_USER_ROLE,
    AUDIT_LOG_SCHEMA,
    SESSIONS_SCHEMA,
    BLANKS_SCHEMA,
    ORDER_ITEM_BLANKS_SCHEMA,
)
from ._helpers import (  # noqa: F401
    _normalize_accessory_name,
    _guard_add_column,
    _guard_drop_column,
    _seed_expense_categories,
    _seed_chart_of_accounts,
    _ensure_staff_payable_sub_account,
    _ensure_ap_vendor_sub_account,
    _account_id_by_code,
    _insert_journal_entry,
    _backfill_expense_journal_entries,
    _backfill_payment_transaction_journal_entries,
    _backfill_delivered_order_journal_entries,
    _backfill_journal_transaction_date,
    _baseline_cost_for_product,
    _backfill_order_items_cost_at_sale,
    _strip_diacritics,
    _normalize_phone,
    _pick_most_common_name,
    _order_year,
    _recompute_customer_year_summary,
    _repair_null_customer_links,
    ensure_schema,
)
from .registry import MIGRATIONS, ensure_schema  # noqa: F401

from .migrations.v004 import _migrate_v4_assign_codes  # noqa: F401
from .migrations.v005 import _migrate_v5_update_categories  # noqa: F401
from .migrations.v006 import _migrate_v6_seed_variants  # noqa: F401
from .migrations.v008 import _migrate_v8_photos  # noqa: F401
from .migrations.v012 import _migrate_v12_data  # noqa: F401
from .migrations.v014 import _migrate_v14_seed_order_sources  # noqa: F401
from .migrations.v016 import _migrate_v16_staff_and_created_by  # noqa: F401
from .migrations.v017 import _migrate_v17_fix_staff_names  # noqa: F401
from .migrations.v018 import _migrate_v18_seed_checklist  # noqa: F401
from .migrations.v020 import _migrate_v20_seed_shipping_and_extras  # noqa: F401
from .migrations.v023 import _migrate_v23_product_attributes  # noqa: F401
from .migrations.v024 import _migrate_v24_rut_tien_toggle  # noqa: F401
from .migrations.v025 import _migrate_v25_tien_rut_rename  # noqa: F401
from .migrations.v026 import _migrate_v26_trung_bay_and_stock  # noqa: F401
from .migrations.v027 import _migrate_v27_seed_catalog_tags  # noqa: F401
from .migrations.v028 import _migrate_v28_cascade_and_reseed  # noqa: F401
from .migrations.v029 import _migrate_v29_add_pin_support  # noqa: F401
from .migrations.v031 import _migrate_v31_enum_attributes  # noqa: F401
from .migrations.v032 import _migrate_v32_print_tracking  # noqa: F401
from .migrations.v035 import _migrate_v35_reconciliation_line_waste_reason  # noqa: F401
from .migrations.v036 import _migrate_v36_chip_aware_inventory  # noqa: F401
from .migrations.v037 import _migrate_v37_price_bucket_consolidation  # noqa: F401
from .migrations.v038 import _migrate_v38_accessory_products  # noqa: F401
from .migrations.v042 import _migrate_v42_backfill_payment_source  # noqa: F401
from .migrations.v043 import _migrate_v43_event_history_and_soft_delete  # noqa: F401
from .migrations.v044 import _migrate_v44_double_entry_accounting  # noqa: F401
from .migrations.v045 import _migrate_v45_cost_history_and_cost_at_sale  # noqa: F401
from .migrations.v046 import _migrate_v46_fix_old_expense_journal  # noqa: F401
from .migrations.v047 import _migrate_v47_fix_stale_cogs_entries  # noqa: F401
from .migrations.v048 import _migrate_v48_fix_inventory_purchase_entries  # noqa: F401
from .migrations.v049 import _migrate_v49_bus_shipping_backfill  # noqa: F401
from .migrations.v050 import _migrate_v50_journal_transaction_date  # noqa: F401
from .migrations.v051 import _migrate_v51_backfill_journal_transaction_date  # noqa: F401
from .migrations.v052 import _migrate_v52_reclassify_staff_advances_as_liabilities  # noqa: F401
from .migrations.v053 import _migrate_v53_payment_transaction_invalidation  # noqa: F401
from .migrations.v054 import _migrate_v54_add_account_2400  # noqa: F401
from .migrations.v055 import _migrate_v55_utc_timestamp_standardization  # noqa: F401
from .migrations.v056 import _migrate_v56_customers_and_order_link  # noqa: F401
from .migrations.v057 import _migrate_v57_generate_customers_from_orders  # noqa: F401
from .migrations.v058 import _migrate_v58_customer_phones  # noqa: F401
from .migrations.v059 import _migrate_v59_deduplicate_customers  # noqa: F401
from .migrations.v060 import _migrate_v60_customer_year_summary  # noqa: F401
from .migrations.v061 import _migrate_v61_customer_search_name  # noqa: F401
from .migrations.v062 import _migrate_v62_negative_balance  # noqa: F401
from .migrations.v063 import _migrate_v63_repair_zero_cogs_and_missing_entries  # noqa: F401
from .migrations.v064 import _migrate_v64_delivery_phone  # noqa: F401
from .migrations.v065 import _migrate_v65_journal_sync_failure_log  # noqa: F401
from .migrations.v066 import _migrate_v66_repair_customer_links  # noqa: F401
from .migrations.v068 import _migrate_v68_users_table  # noqa: F401
from .migrations.v071 import _migrate_v71_users_role_check  # noqa: F401
from .migrations.v072 import _migrate_v72_lowercase_usernames  # noqa: F401
from .migrations.v073 import _migrate_v73_add_account_2500  # noqa: F401
from .migrations.v074 import _migrate_v74_backfill_null_customer_links  # noqa: F401
from .migrations.v075 import _migrate_v75_backfill_primary_customer_phones  # noqa: F401
from .migrations.v076 import _migrate_v76_add_transaction_bank_sub_accounts  # noqa: F401
from .migrations.v077 import _migrate_v77_staff_id_columns  # noqa: F401
from .migrations.v078 import _migrate_v78_add_staff_name_to_events  # noqa: F401
from .migrations.v079 import _migrate_v79_add_staff_name_to_orders  # noqa: F401
from .migrations.v080 import _migrate_v80_drop_amount_paid_from_orders  # noqa: F401
from .migrations.v082 import _migrate_v82_add_blank_id_to_order_items  # noqa: F401
from .migrations.v083 import _migrate_v83_order_item_blanks  # noqa: F401
from .migrations.v084 import _migrate_v84_order_item_assigned_price  # noqa: F401
from .migrations.v085 import _migrate_v85_add_account_1600  # noqa: F401
from .migrations.v086 import _migrate_v86_expense_categories  # noqa: F401
from .migrations.v087 import _migrate_v87_order_delivery_schedule_gps  # noqa: F401
from .migrations.v089 import _migrate_v89_order_assigned_staff_id  # noqa: F401
from .migrations.v091 import _migrate_v91_cash_drawer_schema  # noqa: F401
from .migrations.v092 import _migrate_v92_cash_drawer_sub_accounts  # noqa: F401
from .migrations.v093 import _migrate_v93_rename_quy_to_quay_in_journal_entries  # noqa: F401
from .migrations.v094 import _migrate_v94_cash_drawer_tien_rut_columns  # noqa: F401
from .migrations.v095 import _migrate_v95_cash_drawer_journal_balance  # noqa: F401

__all__ = [
    'ACCOUNTING_SCHEMA',
    'ACCOUNTS_PAYABLE_CODE',
    'ACCOUNTS_RECEIVABLE_CODE',
    'ALLOWED_TABLES',
    'APP_CONFIG_AND_ORDER_SOURCE_SCHEMA',
    'AUDIT_LOG_SCHEMA',
    'BLANKS_SCHEMA',
    'BUS_SHIPPING_HELD_CODE',
    'CASH_DRAWER_SCHEMA',
    'CASH_DRAWER_JOURNAL_ENTRIES_SCHEMA',
    'CATALOG_PHOTO_TAGS_SCHEMA',
    'CHECKLIST_SCHEMA',
    'COGS_CODE',
    'COST_HISTORY_SCHEMA',
    'CUSTOMERS_SCHEMA',
    'CUSTOMER_DEPOSITS_CODE',
    'CUSTOMER_PHONES_SCHEMA',
    'CUSTOMER_YEAR_SUMMARY_SCHEMA',
    'EVENT_HISTORY_AND_SOFT_DELETE_SCHEMA',
    'EVENT_PHOTOS_SCHEMA',
    'EXPENSE_CATEGORIES_SCHEMA',
    'EXPENSE_CATEGORY_TO_ACCOUNT_CODE',
    'EXPENSE_DEBT_PAYMENT_METHOD',
    'EXPENSE_PAYMENT_SOURCE_TO_ACCOUNT_CODE',
    'INITIAL_SCHEMA',
    'INVENTORY_CODE',
    'INVENTORY_PURCHASE_CATEGORIES',
    'JOURNAL_SYNC_FAILURE_LOG_SCHEMA',
    'KNOWLEDGE_BASE_SCHEMA',
    'KNOWLEDGE_PIN_SCHEMA',
    'MIGRATIONS',
    'NEGATIVE_BALANCE_SCHEMA',
    'ORDER_HISTORY_SCHEMA',
    'ORDER_INCIDENT_ORDER_ID_SCHEMA',
    'ORDER_ITEMS_AND_PAYMENT_TRANSACTIONS_SCHEMA',
    'ORDER_ITEMS_ATTRIBUTES_SCHEMA',
    'ORDER_ITEM_BLANKS_SCHEMA',
    'ORDER_PHOTOS_SCHEMA',
    'ORDER_REVENUE_CODE',
    'PAYMENT_METHOD_TO_ASSET_CODE',
    'PAYMENT_OUTFLOW_TYPES',
    'PAYMENT_TIEN_RUT_TYPES',
    'PER_ITEM_BIRTHDAY_AND_PHOTO_LINK_SCHEMA',
    'PHOTOS_TABLE_AND_PHOTO_IDS_SCHEMA',
    'PHOTO_PATH_AND_SEED',
    'PHU_KIEN_CATEGORY',
    'PRINT_LOG_AND_PRINTED_BY_SCHEMA',
    'PRODUCT_ATTRIBUTES_SCHEMA',
    'PRODUCT_ATTRIBUTE_OPTIONS_SCHEMA',
    'PRODUCT_CATALOG_PHOTOS_SCHEMA',
    'PRODUCT_CODE_AND_CATEGORIES_SCHEMA',
    'PRODUCT_PRICE_CHIPS_SCHEMA',
    'PRODUCT_STOCK_SCHEMA',
    'PROMO_EXPENSE_CODE',
    'PUBLIC_ORDER_CODE_SCHEMA',
    'RECONCILIATIONS_SCHEMA',
    'RECONCILIATION_SALE_ROWS_SCHEMA',
    'REVENUE_UPDATE_TOLERANCE',
    'SEED_CAKE_VARIANTS',
    'SEED_CATALOG_TAGS',
    'SEED_CATEGORIES',
    'SEED_CHART_OF_ACCOUNTS',
    'SEED_CHECKLIST_CLOSING',
    'SEED_CHECKLIST_OPENING',
    'SEED_EXPENSE_CATEGORIES',
    'SEED_NHAN_BANH_OPTIONS',
    'SEED_ORDER_SOURCES',
    'SEED_PRODUCTS',
    'SEED_PRODUCT_ATTRIBUTES',
    'SEED_SHIPPING_AND_EXTRAS',
    'SEED_STAFF',
    'SEED_SU_KEM_SETS',
    'SERVER_LOGS_AND_TRIGGERS_SCHEMA',
    'SESSIONS_SCHEMA',
    'SHIPPING_FEE_AND_EXTRAS_SCHEMA',
    'STAFF_AND_PEOPLE_SCHEMA',
    'STAFF_PAYABLES_CODE',
    'STOCK_LOTS_AND_ITEMS_SCHEMA',
    'TIEN_RUT_HELD_CODE',
    'TRANSACTION_PAYMENT_SOURCE_TO_ASSET_CODE',
    'UNALLOCATED_BANK_CODE',
    'USERS_SCHEMA',
    'WORK_TICKET_PRINTED_AT_SCHEMA',
    '_OLD_CATEGORY_TO_SLUG',
    '_SEED_STAFF_ROLE_TO_USER_ROLE',
    '_TIMESTAMP_COLUMNS_V55',
    '_account_id_by_code',
    '_backfill_delivered_order_journal_entries',
    '_backfill_expense_journal_entries',
    '_backfill_journal_transaction_date',
    '_backfill_order_items_cost_at_sale',
    '_backfill_payment_transaction_journal_entries',
    '_baseline_cost_for_product',
    '_ensure_ap_vendor_sub_account',
    '_ensure_staff_payable_sub_account',
    '_guard_add_column',
    '_guard_drop_column',
    '_insert_journal_entry',
    '_migrate_v12_data',
    '_migrate_v14_seed_order_sources',
    '_migrate_v16_staff_and_created_by',
    '_migrate_v17_fix_staff_names',
    '_migrate_v18_seed_checklist',
    '_migrate_v20_seed_shipping_and_extras',
    '_migrate_v23_product_attributes',
    '_migrate_v24_rut_tien_toggle',
    '_migrate_v25_tien_rut_rename',
    '_migrate_v26_trung_bay_and_stock',
    '_migrate_v27_seed_catalog_tags',
    '_migrate_v28_cascade_and_reseed',
    '_migrate_v29_add_pin_support',
    '_migrate_v31_enum_attributes',
    '_migrate_v32_print_tracking',
    '_migrate_v35_reconciliation_line_waste_reason',
    '_migrate_v36_chip_aware_inventory',
    '_migrate_v37_price_bucket_consolidation',
    '_migrate_v38_accessory_products',
    '_migrate_v42_backfill_payment_source',
    '_migrate_v43_event_history_and_soft_delete',
    '_migrate_v44_double_entry_accounting',
    '_migrate_v45_cost_history_and_cost_at_sale',
    '_migrate_v46_fix_old_expense_journal',
    '_migrate_v47_fix_stale_cogs_entries',
    '_migrate_v48_fix_inventory_purchase_entries',
    '_migrate_v49_bus_shipping_backfill',
    '_migrate_v4_assign_codes',
    '_migrate_v50_journal_transaction_date',
    '_migrate_v51_backfill_journal_transaction_date',
    '_migrate_v52_reclassify_staff_advances_as_liabilities',
    '_migrate_v53_payment_transaction_invalidation',
    '_migrate_v54_add_account_2400',
    '_migrate_v55_utc_timestamp_standardization',
    '_migrate_v56_customers_and_order_link',
    '_migrate_v57_generate_customers_from_orders',
    '_migrate_v58_customer_phones',
    '_migrate_v59_deduplicate_customers',
    '_migrate_v5_update_categories',
    '_migrate_v60_customer_year_summary',
    '_migrate_v61_customer_search_name',
    '_migrate_v62_negative_balance',
    '_migrate_v63_repair_zero_cogs_and_missing_entries',
    '_migrate_v64_delivery_phone',
    '_migrate_v65_journal_sync_failure_log',
    '_migrate_v66_repair_customer_links',
    '_migrate_v68_users_table',
    '_migrate_v6_seed_variants',
    '_migrate_v71_users_role_check',
    '_migrate_v72_lowercase_usernames',
    '_migrate_v73_add_account_2500',
    '_migrate_v74_backfill_null_customer_links',
    '_migrate_v75_backfill_primary_customer_phones',
    '_migrate_v76_add_transaction_bank_sub_accounts',
    '_migrate_v77_staff_id_columns',
    '_migrate_v78_add_staff_name_to_events',
    '_migrate_v79_add_staff_name_to_orders',
    '_migrate_v80_drop_amount_paid_from_orders',
    '_migrate_v82_add_blank_id_to_order_items',
    '_migrate_v83_order_item_blanks',
    '_migrate_v84_order_item_assigned_price',
    '_migrate_v85_add_account_1600',
    '_migrate_v86_expense_categories',
    '_migrate_v87_order_delivery_schedule_gps',
    '_migrate_v89_order_assigned_staff_id',
    '_migrate_v8_photos',
    '_migrate_v91_cash_drawer_schema',
    '_migrate_v92_cash_drawer_sub_accounts',
    '_migrate_v93_rename_quy_to_quay_in_journal_entries',
    '_migrate_v94_cash_drawer_tien_rut_columns',
    '_migrate_v95_cash_drawer_journal_balance',
    '_normalize_accessory_name',
    '_normalize_phone',
    '_order_year',
    '_pick_most_common_name',
    '_recompute_customer_year_summary',
    '_repair_null_customer_links',
    '_seed_chart_of_accounts',
    '_seed_expense_categories',
    '_strip_diacritics',
    'ensure_schema',
]
