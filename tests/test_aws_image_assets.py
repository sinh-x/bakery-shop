"""Static contracts for reproducible, non-root AWS application images."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]


def test_backend_preserves_efs_data_dir_non_root_and_healthcheck():
    dockerfile = (ROOT / "Dockerfile").read_text()
    assert "ENV BAKER_DATA_DIR=/var/lib/baker" in dockerfile
    assert "USER baker" in dockerfile
    assert "HEALTHCHECK" in dockerfile
    assert "/api/health" in dockerfile


def test_auth_required_startup_rejects_ephemeral_jwt_configuration():
    config = (ROOT / "src/baker/config.py").read_text()
    assert "if AUTH_REQUIRED:" in config
    assert "Authentication-required startup needs stable JWT configuration" in config


def test_web_image_and_caddy_support_alb_task_local_health():
    dockerfile = (ROOT / "docker/aws/Dockerfile.web").read_text()
    caddyfile = (ROOT / "docker/aws/Caddyfile").read_text()
    assert "ghcr.io/cirruslabs/flutter:3.44.0@sha256:" in dockerfile
    assert "caddy:2.10.2-alpine@sha256:" in dockerfile
    assert "USER caddy" in dockerfile
    assert "HEALTHCHECK" in dockerfile
    assert 'http://127.0.0.1:8080/healthz' in dockerfile

    health_handler = re.search(
        r'handle /healthz\s*\{\s*respond "([^"]*)" (\d+)\s*\}',
        caddyfile,
    )
    assert health_handler is not None
    probe_body, probe_status = health_handler.groups()
    assert probe_status == "200"
    assert probe_body == "ok"
    assert "<!DOCTYPE html>" not in probe_body

    api_handler = re.search(
        r"handle /api/\*\s*\{\s*reverse_proxy 127\.0\.0\.1:2108\s*\}",
        caddyfile,
    )
    assert api_handler is not None
    assert caddyfile.index("handle /healthz") < caddyfile.index("handle {")
    assert caddyfile.index("handle /api/*") < caddyfile.index("handle {")
    assert "tls " not in caddyfile


def test_backup_image_pins_tool_versions_checksums_and_user():
    dockerfile = (ROOT / "docker/aws/Dockerfile.backup").read_text()
    assert "RUSTIC_VERSION=0.11.4" in dockerfile
    assert "SQLITE_VERSION=3500400" in dockerfile
    checksums = re.findall(r"SHA256=([0-9a-f]{64})", dockerfile)
    assert len(checksums) == 3
    assert "sha256sum -c -" in dockerfile
    assert "ENV BAKER_DATA_DIR=/var/lib/baker" in dockerfile
    assert "USER backup" in dockerfile
    assert 'ENTRYPOINT ["/usr/local/bin/aws-backup.sh"]' in dockerfile


def test_backup_script_has_lock_integrity_manifest_and_retention_contracts():
    script = (ROOT / "scripts/aws-backup.sh").read_text()
    assert 'LOCK_DIR="$DATA_DIR/.backup.lock"' in script
    assert ".backup '$DB_DST'" in script
    assert "PRAGMA integrity_check" in script
    assert "SELECT hash FROM photos ORDER BY hash" in script
    assert "SHA256SUMS" in script
    assert '--filter-host "$BACKUP_HOST"' in script
    assert "--filter-paths-exact /baker" in script
    assert "--filter-tags type=hourly" in script
    assert "--keep-hourly 48" in script
    assert "--keep-daily 7" in script
    assert "--keep-weekly 4" in script
    assert "--keep-monthly 3" in script
