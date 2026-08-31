"""Static and hermetic execution tests for the AWS backup image contract."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess


REPO_ROOT = Path(__file__).resolve().parents[1]
BACKUP_SCRIPT = REPO_ROOT / "scripts" / "aws-backup.sh"
VERIFY_SCRIPT = REPO_ROOT / "scripts" / "verify-backup-restore.sh"


def _make_data_dir(tmp_path: Path, *, include_photo: bool = True) -> tuple[Path, str]:
    data_dir = tmp_path / "data"
    photos_dir = data_dir / "photos"
    photos_dir.mkdir(parents=True)
    photo_hash = "a" * 64
    with sqlite3.connect(data_dir / "baker.db") as conn:
        conn.execute("CREATE TABLE photos (hash TEXT UNIQUE NOT NULL)")
        conn.execute("INSERT INTO photos (hash) VALUES (?)", (photo_hash,))
    if include_photo:
        (photos_dir / f"{photo_hash}.jpg").write_bytes(b"fixture-photo")
    return data_dir, photo_hash


def _make_fake_rustic(tmp_path: Path) -> tuple[Path, Path, Path]:
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    log_path = tmp_path / "rustic-commands.jsonl"
    capture_path = tmp_path / "captured-stage"
    rustic = fake_bin / "rustic"
    rustic.write_text(
        """#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shutil
import sys

args = sys.argv[1:]
with open(os.environ["FAKE_RUSTIC_LOG"], "a") as handle:
    handle.write(json.dumps(args) + "\\n")
command = next((item for item in args if item in {"snapshots", "backup", "forget"}), "")
if command == "backup":
    source = Path(args[args.index("backup") + 1])
    capture = Path(os.environ["FAKE_RUSTIC_CAPTURE"])
    if capture.exists():
        shutil.rmtree(capture)
    shutil.copytree(source, capture)
if os.environ.get("FAKE_RUSTIC_FAIL_ON") == command:
    sys.exit(42)
"""
    )
    rustic.chmod(0o755)
    sqlite_cli = fake_bin / "sqlite3"
    sqlite_cli.write_text(
        """#!/usr/bin/env python3
import shlex
import sqlite3
import sys

args = sys.argv[1:]
if args == ["--version"]:
    print("3.50.4 2025-07-30")
    raise SystemExit(0)
if args[0] == "-noheader":
    args = args[1:]
database, commands = args[0], args[1:]
for command in commands:
    if command.startswith(".timeout"):
        continue
    if command.startswith(".backup"):
        destination = shlex.split(command)[1]
        with sqlite3.connect(database) as source, sqlite3.connect(destination) as target:
            source.backup(target)
        continue
    with sqlite3.connect(database) as connection:
        for row in connection.execute(command):
            print("|".join(str(value) for value in row))
"""
    )
    sqlite_cli.chmod(0o755)
    return fake_bin, log_path, capture_path


def _run_backup(
    tmp_path: Path,
    data_dir: Path,
    *,
    fail_on: str = "",
) -> tuple[subprocess.CompletedProcess[str], Path, Path]:
    fake_bin, log_path, capture_path = _make_fake_rustic(tmp_path)
    staging_root = tmp_path / "staging"
    env = os.environ.copy()
    env.update(
        {
            "DATA_DIR": str(data_dir),
            "STAGING_ROOT": str(staging_root),
            "RUSTIC_PROFILE": "",
            "FAKE_RUSTIC_LOG": str(log_path),
            "FAKE_RUSTIC_CAPTURE": str(capture_path),
            "FAKE_RUSTIC_FAIL_ON": fail_on,
            "PATH": f"{fake_bin}:{env['PATH']}",
        }
    )
    result = subprocess.run(
        [str(BACKUP_SCRIPT)],
        text=True,
        capture_output=True,
        env=env,
        check=False,
    )
    return result, log_path, capture_path


def _commands(log_path: Path) -> list[list[str]]:
    if not log_path.exists():
        return []
    return [json.loads(line) for line in log_path.read_text().splitlines()]


def test_backup_stages_verified_db_photos_manifest_and_retention(tmp_path):
    data_dir, photo_hash = _make_data_dir(tmp_path)
    result, log_path, capture_path = _run_backup(tmp_path, data_dir)

    assert result.returncode == 0, result.stderr
    commands = _commands(log_path)
    assert [next(item for item in args if item in {"snapshots", "backup", "forget"}) for args in commands] == [
        "snapshots",
        "backup",
        "forget",
    ]
    backup = commands[-2]
    assert backup[backup.index("--host") + 1] == "baker-aws-prod"
    forget = commands[-1]
    assert forget[forget.index("--filter-host") + 1] == "baker-aws-prod"
    assert forget[forget.index("--filter-paths-exact") + 1] == "/baker"
    assert forget[forget.index("--filter-tags") + 1] == "type=hourly"
    assert forget[forget.index("--keep-hourly") + 1] == "48"
    assert forget[forget.index("--keep-daily") + 1] == "7"
    assert forget[forget.index("--keep-weekly") + 1] == "4"
    assert forget[forget.index("--keep-monthly") + 1] == "3"
    assert (capture_path / "baker.db").is_file()
    assert (capture_path / "photos" / f"{photo_hash}.jpg").is_file()
    assert (capture_path / "SHA256SUMS").is_file()
    assert not (data_dir / ".backup.lock").exists()
    assert not any((tmp_path / "staging").iterdir())


def test_backup_overlap_fails_without_removing_other_owner_lock(tmp_path):
    data_dir, _ = _make_data_dir(tmp_path)
    (data_dir / ".backup.lock").mkdir()
    result, log_path, _ = _run_backup(tmp_path, data_dir)

    assert result.returncode != 0
    assert "another backup holds" in result.stderr
    assert (data_dir / ".backup.lock").is_dir()
    assert _commands(log_path) == []


def test_backup_missing_referenced_photo_fails_and_cleans_up(tmp_path):
    data_dir, _ = _make_data_dir(tmp_path, include_photo=False)
    result, log_path, _ = _run_backup(tmp_path, data_dir)

    assert result.returncode != 0
    assert "database-referenced photo is missing" in result.stderr
    assert [args[0] for args in _commands(log_path)] == ["snapshots"]
    assert not (data_dir / ".backup.lock").exists()
    assert not any((tmp_path / "staging").iterdir())


def test_backup_upload_failure_is_terminal_and_cleans_up(tmp_path):
    data_dir, _ = _make_data_dir(tmp_path)
    result, log_path, _ = _run_backup(tmp_path, data_dir, fail_on="backup")

    assert result.returncode == 42
    assert any("backup" in args for args in _commands(log_path))
    assert not any("forget" in args for args in _commands(log_path))
    assert not (data_dir / ".backup.lock").exists()
    assert not any((tmp_path / "staging").iterdir())


def test_backup_retention_failure_is_terminal_and_cleans_up(tmp_path):
    data_dir, _ = _make_data_dir(tmp_path)
    result, log_path, _ = _run_backup(tmp_path, data_dir, fail_on="forget")

    assert result.returncode == 42
    assert any("forget" in args for args in _commands(log_path))
    assert not (data_dir / ".backup.lock").exists()
    assert not any((tmp_path / "staging").iterdir())


def test_restore_validator_rejects_manifest_mismatch(tmp_path):
    data_dir, photo_hash = _make_data_dir(tmp_path)
    isolated = tmp_path / "isolated-restore"
    shutil.copytree(data_dir, isolated)
    files = [isolated / "baker.db", isolated / "photos" / f"{photo_hash}.jpg"]
    lines = []
    for path in files:
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        lines.append(f"{digest}  ./{path.relative_to(isolated)}")
    (isolated / "SHA256SUMS").write_text("\n".join(lines) + "\n")
    files[1].write_bytes(b"tampered-photo")

    result = subprocess.run(
        [str(VERIFY_SCRIPT), str(isolated)],
        text=True,
        capture_output=True,
        env={**os.environ, "BAKER_DATA_DIR": str(data_dir)},
        check=False,
    )
    assert result.returncode != 0
    assert "did NOT match" in result.stderr


def test_restore_validator_refuses_active_data_directory(tmp_path):
    data_dir, _ = _make_data_dir(tmp_path)
    result = subprocess.run(
        [str(VERIFY_SCRIPT), str(data_dir)],
        text=True,
        capture_output=True,
        env={**os.environ, "BAKER_DATA_DIR": str(data_dir)},
        check=False,
    )
    assert result.returncode != 0
    assert "refusing to validate the production data directory" in result.stderr
