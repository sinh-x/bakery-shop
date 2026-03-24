"""FastAPI application for Baker API."""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from baker.api.cake_queue import router as cake_queue_router
from baker.api.catalog import router as catalog_router
from baker.api.categories import router as categories_router
from baker.api.config import router as config_router
from baker.api.events import router as events_router
from baker.api.exception_handlers import global_exception_handler
from baker.api.middleware import LoggingMiddleware
from baker.api.order_photos import router as order_photos_router
from baker.api.orders import router as orders_router
from baker.api.payment_transactions import router as payment_transactions_router
from baker.api.photos import router as photos_router
from baker.api.products import router as products_router
from baker.api.staff import router as staff_router
from baker.api.work_items import router as work_items_router
from baker.config import VERSION
from baker.logging import setup_logging


def create_app() -> FastAPI:
    """Create and configure the FastAPI application."""
    app = FastAPI(
        title="Baker API",
        description="Bakery shop operations API",
        version=VERSION,
    )

    # Initialize logging
    setup_logging()

    # Register global exception handler
    app.add_exception_handler(Exception, global_exception_handler)

    # Logging middleware (added before CORS so it wraps all requests)
    app.add_middleware(LoggingMiddleware)

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

    app.include_router(photos_router)
    app.include_router(products_router)
    app.include_router(catalog_router)
    app.include_router(categories_router)
    app.include_router(config_router)
    app.include_router(events_router)
    app.include_router(orders_router)
    app.include_router(order_photos_router)
    app.include_router(work_items_router)
    app.include_router(payment_transactions_router)
    app.include_router(cake_queue_router)
    app.include_router(staff_router)

    return app
