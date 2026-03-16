"""Serve command — start the FastAPI server."""

import click


@click.command("serve")
@click.option("--host", default="0.0.0.0", help="Bind host")
@click.option("--port", default=8000, type=int, help="Bind port")
@click.option("--reload", is_flag=True, help="Auto-reload on code changes")
def serve_cmd(host: str, port: int, reload: bool):
    """Start the Baker API server."""
    import uvicorn

    click.echo(f"Starting Baker API on {host}:{port}")
    uvicorn.run(
        "baker.api.app:create_app",
        factory=True,
        host=host,
        port=port,
        reload=reload,
    )
