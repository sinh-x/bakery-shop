"""Migration v017: _migrate_v17_fix_staff_names (extracted from schema.py)."""

from .._constants import *  # noqa: F401,F403
from .._helpers import *  # noqa: F401,F403

def _migrate_v17_fix_staff_names(conn):
    """Fix staff names to use proper Vietnamese diacritics."""
    fixes = [
        ("An", "Ân"),
        ("Ngan", "Ngân"),
        ("Phuong", "Phượng"),
        ("Tan", "Tân"),
    ]
    for old_name, new_name in fixes:
        conn.execute(
            "UPDATE staff SET name = ? WHERE name = ?",
            (new_name, old_name),
        )
