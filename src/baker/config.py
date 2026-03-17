import os
from pathlib import Path

import yaml

APP_NAME = "baker"
VERSION = "0.1.0"

_DEFAULT_CONFIG_PATH = Path.home() / ".config" / "doangia" / "bakery" / "baker.yaml"
_CONFIG_PATH = Path(os.environ.get("BAKER_CONFIG", _DEFAULT_CONFIG_PATH))


def _load_config() -> dict:
    if _CONFIG_PATH.exists():
        with open(_CONFIG_PATH) as f:
            return yaml.safe_load(f) or {}
    return {}


_cfg = _load_config()

_project_root = Path(__file__).resolve().parents[2]
_default_data_dir = _project_root / "data"

DATA_DIR = Path(_cfg.get("data_dir", _default_data_dir)).expanduser()
DB_PATH = Path(_cfg.get("db_path", DATA_DIR / "baker.db")).expanduser()

# Photo storage
PHOTOS_DIR = DATA_DIR / "photos" / "products"

# Server
HOST = _cfg.get("host", "0.0.0.0")
PORT = int(_cfg.get("port", 2108))

# Defaults
DEFAULT_EVENT_TYPE = "note"
ORDER_REF_PREFIX = "ORD"
