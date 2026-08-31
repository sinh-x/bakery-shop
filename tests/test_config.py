"""Dedicated tests for baker.config (FR-PY-6).

Covers reload(), env-var overrides, timezone fallback, JWT secret handling,
bcrypt rounds clamping, delivery critical threshold validation, and
get_delivery_critical_threshold() DB override resolution.
"""

import os

import pytest

import baker.config

# Snapshot of config globals to restore after each test so reload() side
# effects don't leak into other modules (e.g. test_auth captures JWT_SECRET
# at import time and would break if a config test regenerated the secret).
_CONFIG_GLOBALS = [
    "DATA_DIR", "DB_PATH", "PHOTOS_DIR", "HOST", "PORT", "LOG_LEVEL", "LOG_DIR",
    "BUILD_FINGERPRINT", "PRINT_IPP_URL", "PRINT_IPP_SOCKS5", "TIMEZONE", "JWT_SECRET",
    "JWT_SECRET_EPHEMERAL", "AUTH_REQUIRED", "BCRYPT_ROUNDS",
    "DELIVERY_CRITICAL_THRESHOLD_MINUTES", "CORS_ORIGINS",
]


@pytest.fixture(autouse=True)
def _restore_config_globals():
    snapshot = {k: getattr(baker.config, k, None) for k in _CONFIG_GLOBALS}
    yield
    for k in snapshot:
        setattr(baker.config, k, snapshot[k])


def test_reload_loads_defaults(monkeypatch):
    # Clear all BAKER_* env vars so reload picks up built-in defaults.
    for key in list(os.environ):
        if key.startswith("BAKER_"):
            monkeypatch.delenv(key, raising=False)
    baker.config.reload()
    assert baker.config.HOST == "0.0.0.0"
    assert baker.config.PORT == 2108
    assert baker.config.LOG_LEVEL == "INFO"
    assert baker.config.BUILD_FINGERPRINT == "unknown"
    assert baker.config.PRINT_IPP_URL is None
    assert baker.config.PRINT_IPP_SOCKS5 is None


def test_reload_reads_env_vars(monkeypatch):
    monkeypatch.setenv("BAKER_HOST", "127.0.0.1")
    monkeypatch.setenv("BAKER_PORT", "9999")
    monkeypatch.setenv("BAKER_LOG_LEVEL", "debug")
    monkeypatch.setenv("BAKER_BUILD_FINGERPRINT", "fp-abc")
    monkeypatch.setenv("BAKER_PRINT_IPP_URL", "ipp://printer")
    monkeypatch.setenv("BAKER_PRINT_IPP_SOCKS5", "127.0.0.1:1055")
    monkeypatch.setenv("BAKER_TIMEZONE", "Asia/Bangkok")
    monkeypatch.setenv("BAKER_JWT_SECRET", "secret-key")
    monkeypatch.setenv("BAKER_AUTH_REQUIRED", "true")
    baker.config.reload()
    assert baker.config.HOST == "127.0.0.1"
    assert baker.config.PORT == 9999
    assert baker.config.LOG_LEVEL == "DEBUG"
    assert baker.config.BUILD_FINGERPRINT == "fp-abc"
    assert baker.config.PRINT_IPP_URL == "ipp://printer"
    assert baker.config.PRINT_IPP_SOCKS5 == "127.0.0.1:1055"
    assert str(baker.config.TIMEZONE) == "Asia/Bangkok"
    assert baker.config.JWT_SECRET == "secret-key"
    assert baker.config.JWT_SECRET_EPHEMERAL is False
    assert baker.config.AUTH_REQUIRED is True


def test_reload_rejects_invalid_ipp_socks5_endpoint(monkeypatch):
    monkeypatch.setenv("BAKER_PRINT_IPP_SOCKS5", "missing-port")
    with pytest.raises(ValueError, match="host:port"):
        baker.config.reload()


def test_reload_ipp_socks5_error_redacts_endpoint(monkeypatch):
    marker = "private-proxy-marker"
    monkeypatch.setenv("BAKER_PRINT_IPP_SOCKS5", f"user:{marker}@127.0.0.1:1055")
    with pytest.raises(ValueError) as exc_info:
        baker.config.reload()
    assert marker not in str(exc_info.value)


def test_reload_invalid_timezone_falls_back(monkeypatch):
    monkeypatch.setenv("BAKER_TIMEZONE", "Invalid/Zone")
    baker.config.reload()
    assert str(baker.config.TIMEZONE) == "Asia/Ho_Chi_Minh"


def test_reload_generates_ephemeral_jwt_when_unset(monkeypatch):
    monkeypatch.delenv("BAKER_JWT_SECRET", raising=False)
    baker.config.reload()
    assert baker.config.JWT_SECRET != ""
    assert baker.config.JWT_SECRET_EPHEMERAL is True


def test_reload_auth_required_fails_without_stable_jwt(monkeypatch):
    monkeypatch.setenv("BAKER_AUTH_REQUIRED", "true")
    monkeypatch.delenv("BAKER_JWT_SECRET", raising=False)
    with pytest.raises(RuntimeError, match="stable JWT configuration"):
        baker.config.reload()


def test_reload_bcrypt_rounds_clamps_below_four(monkeypatch):
    monkeypatch.setenv("BAKER_BCRYPT_ROUNDS", "2")
    baker.config.reload()
    assert baker.config.BCRYPT_ROUNDS == 12


def test_reload_bcrypt_rounds_invalid_falls_back(monkeypatch):
    monkeypatch.setenv("BAKER_BCRYPT_ROUNDS", "not-a-number")
    baker.config.reload()
    assert baker.config.BCRYPT_ROUNDS == 12


def test_reload_bcrypt_rounds_accepts_valid(monkeypatch):
    monkeypatch.setenv("BAKER_BCRYPT_ROUNDS", "6")
    baker.config.reload()
    assert baker.config.BCRYPT_ROUNDS == 6


def test_reload_delivery_threshold_default(monkeypatch):
    monkeypatch.delenv("BAKER_DELIVERY_CRITICAL_THRESHOLD_MINUTES", raising=False)
    baker.config.reload()
    assert baker.config.DELIVERY_CRITICAL_THRESHOLD_MINUTES == 60


def test_reload_delivery_threshold_invalid_falls_back(monkeypatch):
    monkeypatch.setenv("BAKER_DELIVERY_CRITICAL_THRESHOLD_MINUTES", "garbage")
    baker.config.reload()
    assert baker.config.DELIVERY_CRITICAL_THRESHOLD_MINUTES == 60


def test_reload_delivery_threshold_out_of_range_low(monkeypatch):
    monkeypatch.setenv("BAKER_DELIVERY_CRITICAL_THRESHOLD_MINUTES", "0")
    baker.config.reload()
    assert baker.config.DELIVERY_CRITICAL_THRESHOLD_MINUTES == 60


def test_reload_delivery_threshold_out_of_range_high(monkeypatch):
    monkeypatch.setenv("BAKER_DELIVERY_CRITICAL_THRESHOLD_MINUTES", "10081")
    baker.config.reload()
    assert baker.config.DELIVERY_CRITICAL_THRESHOLD_MINUTES == 60


def test_reload_delivery_threshold_valid(monkeypatch):
    monkeypatch.setenv("BAKER_DELIVERY_CRITICAL_THRESHOLD_MINUTES", "120")
    baker.config.reload()
    assert baker.config.DELIVERY_CRITICAL_THRESHOLD_MINUTES == 120


# --- CORS_ORIGINS parsing tests (DG-345 review r2 CQ-2) ---


def test_cors_origins_default_fallback(monkeypatch):
    """Unset BAKER_CORS_ORIGINS falls back to the default production origin."""
    monkeypatch.delenv("BAKER_CORS_ORIGINS", raising=False)
    baker.config.reload()
    assert baker.config.CORS_ORIGINS == ["https://lily.tail10c2c6.ts.net"]


def test_cors_origins_comma_separated(monkeypatch):
    """Comma-separated origins are parsed into a list."""
    monkeypatch.setenv(
        "BAKER_CORS_ORIGINS",
        "https://lily.tail10c2c6.ts.net,http://localhost:2380,https://bakery.example.com",
    )
    baker.config.reload()
    assert baker.config.CORS_ORIGINS == [
        "https://lily.tail10c2c6.ts.net",
        "http://localhost:2380",
        "https://bakery.example.com",
    ]


def test_cors_origins_whitespace_trimming(monkeypatch):
    """Whitespace around origins is stripped."""
    monkeypatch.setenv(
        "BAKER_CORS_ORIGINS",
        "  https://lily.tail10c2c6.ts.net ,  http://localhost:2380  ",
    )
    baker.config.reload()
    assert baker.config.CORS_ORIGINS == [
        "https://lily.tail10c2c6.ts.net",
        "http://localhost:2380",
    ]


def test_cors_origins_trailing_comma_empty_segments(monkeypatch):
    """Trailing commas and empty segments are dropped."""
    monkeypatch.setenv(
        "BAKER_CORS_ORIGINS",
        "https://lily.tail10c2c6.ts.net,,  ,http://localhost:2380,",
    )
    baker.config.reload()
    assert baker.config.CORS_ORIGINS == [
        "https://lily.tail10c2c6.ts.net",
        "http://localhost:2380",
    ]


def test_cors_origins_whitespace_only_falls_back(monkeypatch):
    """Whitespace-only input falls back to the default origin."""
    monkeypatch.setenv("BAKER_CORS_ORIGINS", "   ")
    baker.config.reload()
    assert baker.config.CORS_ORIGINS == ["https://lily.tail10c2c6.ts.net"]


def test_cors_origins_scheme_missing_warns(monkeypatch, recwarn):
    """SEC-1: origins without a URL scheme trigger a warning."""
    monkeypatch.setenv("BAKER_CORS_ORIGINS", "lily.tail10c2c6.ts.net,http://ok:2380")
    baker.config.reload()
    assert baker.config.CORS_ORIGINS == ["lily.tail10c2c6.ts.net", "http://ok:2380"]
    # At least one warning about the schemeless origin should be emitted.
    scheme_warnings = [
        w for w in recwarn.list
        if "no URL scheme" in str(w.message)
    ]
    assert len(scheme_warnings) >= 1


def test_cors_origins_all_valid_no_warning(monkeypatch, recwarn):
    """No scheme warning when all origins have valid schemes."""
    monkeypatch.setenv(
        "BAKER_CORS_ORIGINS",
        "https://lily.tail10c2c6.ts.net,http://localhost:2380",
    )
    baker.config.reload()
    scheme_warnings = [
        w for w in recwarn.list
        if "no URL scheme" in str(w.message)
    ]
    assert len(scheme_warnings) == 0


def test_reload_from_yaml_file(tmp_path, monkeypatch):
    # Create a custom config YAML.
    cfg_path = tmp_path / "baker.yaml"
    cfg_path.write_text("host: 1.2.3.4\nport: 5555\nlog_level: warning\n")
    monkeypatch.delenv("BAKER_HOST", raising=False)
    monkeypatch.delenv("BAKER_PORT", raising=False)
    baker.config.reload(cfg_path)
    assert baker.config.HOST == "1.2.3.4"
    assert baker.config.PORT == 5555
    assert baker.config.LOG_LEVEL == "WARNING"


def test_get_delivery_critical_threshold_db_override(use_memory_db, api_client):
    # Insert an active app_config override row.
    from baker.db.connection import get_db

    with get_db() as conn:
        conn.execute(
            "INSERT INTO app_config (config_key, config_value, active) "
            "VALUES (?, ?, 1)",
            ("delivery_critical_threshold_minutes", "90"),
        )
    with get_db() as conn:
        result = baker.config.get_delivery_critical_threshold(conn)
    assert result == 90


def test_get_delivery_critical_threshold_db_override_inactive(use_memory_db, api_client):
    # Inactive override should fall back to the env default.
    from baker.db.connection import get_db

    with get_db() as conn:
        conn.execute(
            "INSERT INTO app_config (config_key, config_value, active) "
            "VALUES (?, ?, 0)",
            ("delivery_critical_threshold_minutes", "90"),
        )
    with get_db() as conn:
        result = baker.config.get_delivery_critical_threshold(conn)
    assert result == baker.config.DELIVERY_CRITICAL_THRESHOLD_MINUTES


def test_get_delivery_critical_threshold_db_override_invalid(use_memory_db, api_client):
    # Non-int DB value should fall back to the env default.
    from baker.db.connection import get_db

    with get_db() as conn:
        conn.execute(
            "INSERT INTO app_config (config_key, config_value, active) "
            "VALUES (?, ?, 1)",
            ("delivery_critical_threshold_minutes", "not-a-number"),
        )
    with get_db() as conn:
        result = baker.config.get_delivery_critical_threshold(conn)
    assert result == baker.config.DELIVERY_CRITICAL_THRESHOLD_MINUTES


def test_get_delivery_critical_threshold_db_override_out_of_range(use_memory_db, api_client):
    # Out-of-range DB value should fall back to the env default.
    from baker.db.connection import get_db

    with get_db() as conn:
        conn.execute(
            "INSERT INTO app_config (config_key, config_value, active) "
            "VALUES (?, ?, 1)",
            ("delivery_critical_threshold_minutes", "99999"),
        )
    with get_db() as conn:
        result = baker.config.get_delivery_critical_threshold(conn)
    assert result == baker.config.DELIVERY_CRITICAL_THRESHOLD_MINUTES