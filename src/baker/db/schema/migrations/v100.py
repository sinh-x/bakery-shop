"""Migration v100: _migrate_v100_message_templates (DG-375 Phase 4.1).

Creates the ``message_templates`` table and seeds the 8 default built-in
templates across 6 scenarios (ask_info, confirm_order ×3, final_message,
follow_up, status_update, payment_request). All seeded templates are
system templates (``is_system = 1``) so they are visible to all staff
(FR9 / AC9).

The table schema is applied via the ``MESSAGE_TEMPLATES_SCHEMA`` SQL block
registered in ``MIGRATIONS[100]["sql"]``; this callable only handles the
idempotent seed insert (``INSERT OR IGNORE`` so re-running v100 on an
already-migrated DB is a no-op).
"""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403


def _migrate_v100_message_templates(conn):
    """Seed the 8 default built-in message templates (FR9 / AC9).

    Idempotent: each row uses ``INSERT OR IGNORE`` keyed on the
    ``(scenario, name)`` pair via a unique index, so re-running the
    migration on an already-seeded DB is a no-op. The seed data is defined
    in ``SEED_MESSAGE_TEMPLATES`` (scenario, name, body, sort_order).
    """
    for scenario, name, body, sort_order in SEED_MESSAGE_TEMPLATES:
        conn.execute(
            "INSERT OR IGNORE INTO message_templates "
            "(scenario, name, body, is_system, sort_order, active) "
            "VALUES (?, ?, ?, 1, ?, 1)",
            (scenario, name, body, sort_order),
        )