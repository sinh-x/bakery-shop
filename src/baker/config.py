import os
from pathlib import Path

APP_NAME = "baker"
VERSION = "0.1.0"

# Database location
_project_root = Path(__file__).resolve().parents[2]
DATA_DIR = Path(os.environ.get("BAKER_DATA_DIR", _project_root / "data"))
DB_PATH = Path(os.environ.get("BAKER_DB", DATA_DIR / "baker.db"))

# Defaults
DEFAULT_EVENT_TYPE = "note"
ORDER_REF_PREFIX = "ORD"
