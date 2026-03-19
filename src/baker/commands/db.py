import click
from baker.db.connection import get_db
from baker.db.schema import MIGRATIONS


@click.group("db")
def db_cmd():
    """Database management commands."""
    pass


@db_cmd.command("status")
def db_status():
    """Show current schema version and pending migrations."""
    with get_db() as conn:
        # Check if schema_version table exists
        row = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_version'"
        ).fetchone()
        if not row:
            current = 0
        else:
            row = conn.execute("SELECT MAX(version) FROM schema_version").fetchone()
            current = row[0] if row[0] else 0

        latest = max(MIGRATIONS.keys())
        pending = [v for v in sorted(MIGRATIONS.keys()) if v > current]

        click.echo(f"Current schema version : {current}")
        click.echo(f"Latest available       : {latest}")
        if pending:
            click.echo(f"Pending migrations     : {len(pending)}")
            for v in pending:
                click.echo(f"  v{v}: {MIGRATIONS[v]['description']}")
        else:
            click.echo("Status                 : up to date")

        # Show applied migrations
        if current > 0:
            rows = conn.execute(
                "SELECT version, applied_at, description FROM schema_version ORDER BY version"
            ).fetchall()
            click.echo("\nApplied migrations:")
            for r in rows:
                click.echo(f"  v{r['version']} ({r['applied_at'][:16]}): {r['description']}")


@db_cmd.command("migrate")
@click.option("--backup/--no-backup", default=True, help="Backup before migrating (default: yes)")
@click.option("--dry-run", is_flag=True, help="Show pending migrations without applying them")
def db_migrate(backup, dry_run):
    """Apply pending schema migrations.

    Automatically backs up the database before running migrations (use --no-backup to skip).
    Safe to run multiple times — already-applied migrations are skipped.
    """
    import baker.config
    from baker.db.schema import ensure_schema

    with get_db() as conn:
        row = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='schema_version'"
        ).fetchone()
        current = 0
        if row:
            r = conn.execute("SELECT MAX(version) FROM schema_version").fetchone()
            current = r[0] if r[0] else 0

        pending = [v for v in sorted(MIGRATIONS.keys()) if v > current]

        if not pending:
            click.echo(f"Already up to date (schema version {current}).")
            return

        click.echo(f"Current version: v{current}")
        click.echo(f"Pending ({len(pending)}):")
        for v in pending:
            click.echo(f"  v{v}: {MIGRATIONS[v]['description']}")

        if dry_run:
            click.echo("\nDry run — no changes made.")
            return

        if backup:
            import shutil
            from datetime import datetime
            src = baker.config.DB_PATH
            if src.exists():
                ts = datetime.now().strftime("%Y%m%d-%H%M%S")
                bak = src.parent / f"baker-backup-pre-migrate-{ts}.db"
                shutil.copy2(src, bak)
                click.echo(f"\nBackup: {bak}")

        ensure_schema(conn)
        click.echo(f"\nMigrations applied. Schema is now at v{max(MIGRATIONS.keys())}.")


@db_cmd.command("backup")
@click.option("--dest", default=None, help="Destination file path (default: same dir as DB, timestamped)")
def db_backup(dest):
    """Backup the database to a timestamped file."""
    import shutil
    import baker.config
    from datetime import datetime

    src = baker.config.DB_PATH
    if not src.exists():
        click.echo(f"Error: database not found at {src}", err=True)
        raise SystemExit(1)

    if dest is None:
        ts = datetime.now().strftime("%Y%m%d-%H%M%S")
        dest = src.parent / f"baker-backup-{ts}.db"
    else:
        from pathlib import Path
        dest = Path(dest)

    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)
    size_kb = dest.stat().st_size // 1024
    click.echo(f"Backup created: {dest} ({size_kb} KB)")
