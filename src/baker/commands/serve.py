"""Serve command — start the FastAPI server."""

import click


@click.command("serve")
@click.option("--host", default=None, help="Bind host (overrides config)")
@click.option("--port", default=None, type=int, help="Bind port (overrides config)")
@click.option("--reload", is_flag=True, help="Auto-reload on code changes")
def serve_cmd(host: str | None, port: int | None, reload: bool):
    """Start the Baker API server."""
    import uvicorn
    import baker.config

    h = host or baker.config.HOST
    p = port or baker.config.PORT

    click.echo(f"Starting Baker API on {h}:{p}")
    uvicorn.run(
        "baker.api.app:create_app",
        factory=True,
        host=h,
        port=p,
        reload=reload,
    )
