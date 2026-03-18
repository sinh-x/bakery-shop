"""FastAPI application for Baker API."""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from baker.api.catalog import router as catalog_router
from baker.api.categories import router as categories_router
from baker.api.products import router as products_router
from baker.config import VERSION


def create_app() -> FastAPI:
    """Create and configure the FastAPI application."""
    app = FastAPI(
        title="Baker API",
        description="Bakery shop operations API",
        version=VERSION,
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.get("/api/health")
    def health():
        return {"status": "ok", "version": VERSION}

    app.include_router(products_router)
    app.include_router(catalog_router)
    app.include_router(categories_router)

    return app
