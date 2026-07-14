import os
from importlib.metadata import PackageNotFoundError
from pathlib import Path
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

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
BUILD_FINGERPRINT: str
PRINT_IPP_URL: str | None
TIMEZONE: ZoneInfo
JWT_SECRET: str
JWT_SECRET_EPHEMERAL: bool
AUTH_REQUIRED: bool
BCRYPT_ROUNDS: int


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
    global DATA_DIR, DB_PATH, PHOTOS_DIR, HOST, PORT, LOG_LEVEL, LOG_DIR, BUILD_FINGERPRINT, PRINT_IPP_URL, TIMEZONE, JWT_SECRET, JWT_SECRET_EPHEMERAL, AUTH_REQUIRED, BCRYPT_ROUNDS

    path = Path(config_path).expanduser() if config_path else DEFAULT_CONFIG_PATH
    cfg = _load_from(path)

    DATA_DIR = Path(os.environ.get("BAKER_DATA_DIR") or cfg.get("data_dir", _default_data_dir)).expanduser()
    DB_PATH = Path(cfg.get("db_path", DATA_DIR / "baker.db")).expanduser()
    PHOTOS_DIR = DATA_DIR / "photos"
    HOST = os.environ.get("BAKER_HOST") or cfg.get("host", "0.0.0.0")
    PORT = int(os.environ.get("BAKER_PORT") or cfg.get("port", 2108))
    LOG_LEVEL = (os.environ.get("BAKER_LOG_LEVEL") or cfg.get("log_level", "INFO")).upper()
    LOG_DIR = Path(os.environ.get("BAKER_LOG_DIR") or cfg.get("log_dir", DATA_DIR / "logs")).expanduser()
    BUILD_FINGERPRINT = os.environ.get("BAKER_BUILD_FINGERPRINT") or "unknown"
    PRINT_IPP_URL = os.environ.get("BAKER_PRINT_IPP_URL") or None

    # Configured timezone for display conversion (DG-202 FR4).
    # Default: Asia/Ho_Chi_Minh; override via BAKER_TIMEZONE env var.
    tz_name = os.environ.get("BAKER_TIMEZONE") or cfg.get("timezone", "Asia/Ho_Chi_Minh")
    try:
        TIMEZONE = ZoneInfo(tz_name)
    except ZoneInfoNotFoundError:
        TIMEZONE = ZoneInfo("Asia/Ho_Chi_Minh")

    # JWT secret for auth tokens (DG-029 Phase 1). Minimum 256-bit random key
    # loaded from BAKER_JWT_SECRET. Falls back to an auto-generated key with a
    # warning when unset — grace period behavior (NFR5).
    import logging

    _logger = logging.getLogger("baker.config")
    JWT_SECRET = os.environ.get("BAKER_JWT_SECRET") or ""
    JWT_SECRET_EPHEMERAL = False
    if not JWT_SECRET:
        import secrets

        JWT_SECRET = secrets.token_urlsafe(32)
        JWT_SECRET_EPHEMERAL = True
        _logger.warning(
            "BAKER_JWT_SECRET not set — generated an ephemeral secret. "
            "Tokens will be invalidated on server restart. Set BAKER_JWT_SECRET "
            "in the environment for production use."
        )

    AUTH_REQUIRED = (
        os.environ.get("BAKER_AUTH_REQUIRED", "false").strip().lower() in ("1", "true", "yes", "on")
    )

    # bcrypt work factor for password hashing (NFR4: production default 12).
    # Override via BAKER_BCRYPT_ROUNDS for TEST environments only — lowering this
    # in production weakens password security and violates NFR4. Tests set this
    # to a low value (4) via conftest to keep the suite fast under CI's 10-min cap.
    try:
        BCRYPT_ROUNDS = int(os.environ.get("BAKER_BCRYPT_ROUNDS", "12"))
    except ValueError:
        BCRYPT_ROUNDS = 12
    if BCRYPT_ROUNDS < 4:
        BCRYPT_ROUNDS = 12


# Load defaults on import
reload()
