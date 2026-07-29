"""Migration v055: _migrate_v55_utc_timestamp_standardization (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v55_utc_timestamp_standardization(conn):
    """Append `Z` to bare timestamps and convert `+07:00`-suffixed timestamps
    to UTC `Z` across all in-scope timestamp columns (DG-202 Phase 2).

    Runs as a single transaction (the caller wraps migrations in commit/rollback).
    Idempotent: already-`Z`-suffixed rows are skipped on re-run.
    """
    for table, column in _TIMESTAMP_COLUMNS_V55:
        # 1) Bare timestamps: append 'Z'. Skip rows that already end in 'Z',
        #    have a '+offset' suffix, or are date-only (no 'T').
        conn.execute(
            f"""UPDATE "{table}" SET "{column}" = "{column}" || 'Z'
                WHERE "{column}" IS NOT NULL
                  AND "{column}" != ''
                  AND "{column}" NOT LIKE '%Z'
                  AND "{column}" NOT LIKE '%+%'
                  AND "{column}" LIKE '%T%'""",
        )
        # 2) +07:00-suffixed timestamps: subtract 7 hours and append 'Z'.
        #    Preserve fractional seconds when present (re-append the original
        #    fraction after the strftime, which truncates to whole seconds).
        #    The CASE keeps the whole-seconds path simple while retaining the
        #    fraction for rows that carry one.
        conn.execute(
            f"""UPDATE "{table}" SET "{column}" =
                    CASE
                        WHEN substr("{column}", 20, 1) = '.' THEN
                            strftime('%Y-%m-%dT%H:%M:%S', substr("{column}", 1, 19), '-7 hours')
                            || '.' || substr("{column}", 21, length("{column}") - 26) || 'Z'
                        ELSE
                            strftime('%Y-%m-%dT%H:%M:%SZ', substr("{column}", 1, 19), '-7 hours')
                    END
                WHERE "{column}" LIKE '%+07:00'""",
        )
