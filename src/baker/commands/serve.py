"""Serve command — start the FastAPI server."""

import click


@click.command("serve")
@click.option("--host", default=None, help="Bind host (overrides config)")
@click.option("--port", default=None, type=int, help="Bind port (overrides config)")
@click.option("--reload", is_flag=True, help="Auto-reload on code changes")
@click.option("--log-level", default=None, help="Log level (overrides config)")
def serve_cmd(host: str | None, port: int | None, reload: bool, log_level: str | None):
    """Start the Baker API server."""
    import uvicorn
    import baker.config

    h = host or baker.config.HOST
    p = port or baker.config.PORT
    ll = (log_level or baker.config.LOG_LEVEL).lower()

    click.echo(f"Starting Baker API on {h}:{p} (log_level={ll})")
    uvicorn.run(
        "baker.api.app:create_app",
        factory=True,
        host=h,
        port=p,
        reload=reload,
        log_level=ll,
    )
