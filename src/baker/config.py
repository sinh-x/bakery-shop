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
DELIVERY_CRITICAL_THRESHOLD_MINUTES: int


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
    global DATA_DIR, DB_PATH, PHOTOS_DIR, HOST, PORT, LOG_LEVEL, LOG_DIR, BUILD_FINGERPRINT, PRINT_IPP_URL, TIMEZONE, JWT_SECRET, JWT_SECRET_EPHEMERAL, AUTH_REQUIRED, BCRYPT_ROUNDS, DELIVERY_CRITICAL_THRESHOLD_MINUTES

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

    # Delivery critical threshold (DG-253 Phase 1).
    # Early critical window (minutes) for delivery/bus/door orders so they are
    # highlighted as critical before the due time (prep/transit buffer).
    # Override via BAKER_DELIVERY_CRITICAL_THRESHOLD_MINUTES; default 60.
    # Validates >= 1 and <= 10080 (7 days) on read; out-of-range or invalid
    # values fall back to default 60 (DG-253 review-auto r2 MAJOR — without an
    # upper bound, large values overflow ``timedelta`` in compute_urgency and
    # break all order endpoints with 500s).
    _raw_threshold = os.environ.get("BAKER_DELIVERY_CRITICAL_THRESHOLD_MINUTES", "60").strip()
    try:
        _threshold = int(_raw_threshold)
    except ValueError:
        _threshold = 60
    if _threshold < 1 or _threshold > 10080:
        _threshold = 60
    DELIVERY_CRITICAL_THRESHOLD_MINUTES = _threshold


# Load defaults on import
reload()


# DB-override config keys (DG-253 Phase 1).
# app_config key for runtime override (DB value takes precedence over env var).
DELIVERY_CRITICAL_THRESHOLD_CONFIG_KEY = "delivery_critical_threshold_minutes"


def get_delivery_critical_threshold(conn) -> int:
    """Return the effective delivery critical threshold in minutes for the
    current urgency computation.

    DB override (app_config.delivery_critical_threshold_minutes) takes
    precedence over the env var default (NFR1). Read on each call so
    Settings-screen changes take effect on the next request without a server
    restart (mirrors `paper_mode`/`trail_mm` pattern in usb_printer.py).

    Args:
        conn: SQLite connection (from get_db() context manager).

    Returns:
        Effective threshold in minutes (1..10080). Falls back to
        DELIVERY_CRITICAL_THRESHOLD_MINUTES (env var default) when the DB
        value is missing, inactive, or invalid (out of range / non-int).
    """
    row = conn.execute(
        "SELECT config_value FROM app_config WHERE config_key = ? AND active = 1"
        " ORDER BY id DESC LIMIT 1",
        (DELIVERY_CRITICAL_THRESHOLD_CONFIG_KEY,),
    ).fetchone()
    if row is not None:
        raw = (row["config_value"] or "").strip()
        try:
            value = int(raw)
            if 1 <= value <= 10080:
                return value
        except ValueError:
            pass
    return DELIVERY_CRITICAL_THRESHOLD_MINUTES
