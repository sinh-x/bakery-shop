"""Serve command — start the FastAPI server."""

import click

from baker.config import HOST, PORT


@click.command("serve")
@click.option("--host", default=HOST, help="Bind host")
@click.option("--port", default=PORT, type=int, help="Bind port")
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
