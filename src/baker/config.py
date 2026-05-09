import os
from importlib.metadata import PackageNotFoundError
from pathlib import Path

import yaml

APP_NAME = "baker"
from importlib.metadata import version as _get_version

try:
    VERSION = _get_version("baker")
except PackageNotFoundError:
    VERSION = "0.0.0"

DEFAULT_CONFIG_PATH = Path.home() / ".config" / "doangia" / "bakery" / "baker.yaml"

_project_root = Path(__file__).resolve().parents[2]
_default_data_dir = _project_root / "data"

# These are set at load time and updated by reload()
DATA_DIR: Path
DB_PATH: Path
PHOTOS_DIR: Path
HOST: str
PORT: int
LOG_LEVEL: str
LOG_DIR: Path


def _load_from(path: Path) -> dict:
    if path.exists():
        with open(path) as f:
            return yaml.safe_load(f) or {}
    return {}


def reload(config_path: Path | str | None = None) -> None:
    """Load (or reload) config from the given path.

    Falls back to DEFAULT_CONFIG_PATH, then built-in defaults.
    Called automatically on first import; call again with a path to switch configs.
    """
    global DATA_DIR, DB_PATH, PHOTOS_DIR, HOST, PORT, LOG_LEVEL, LOG_DIR

    path = Path(config_path).expanduser() if config_path else DEFAULT_CONFIG_PATH
    cfg = _load_from(path)

    DATA_DIR = Path(os.environ.get("BAKER_DATA_DIR") or cfg.get("data_dir", _default_data_dir)).expanduser()
    DB_PATH = Path(cfg.get("db_path", DATA_DIR / "baker.db")).expanduser()
    PHOTOS_DIR = DATA_DIR / "photos"
    HOST = os.environ.get("BAKER_HOST") or cfg.get("host", "0.0.0.0")
    PORT = int(os.environ.get("BAKER_PORT") or cfg.get("port", 2108))
    LOG_LEVEL = (os.environ.get("BAKER_LOG_LEVEL") or cfg.get("log_level", "INFO")).upper()
    LOG_DIR = Path(os.environ.get("BAKER_LOG_DIR") or cfg.get("log_dir", DATA_DIR / "logs")).expanduser()


# Load defaults on import
reload()
