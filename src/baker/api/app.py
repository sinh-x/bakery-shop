"""FastAPI application for Baker API."""

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from baker.api.cake_queue import router as cake_queue_router
from baker.api.catalog import catalog_router as catalog_browse_router
from baker.api.catalog import router as catalog_router
from baker.api.checklist import router as checklist_router
from baker.api.categories import router as categories_router
from baker.api.config import router as config_router
from baker.api.events import router as events_router
from baker.api.exception_handlers import global_exception_handler
from baker.api.knowledge import router as knowledge_router
from baker.api.middleware import LoggingMiddleware
from baker.api.order_photos import router as order_photos_router
from baker.api.orders import router as orders_router
from baker.api.payment_transactions import router as payment_transactions_router
from baker.api.printing import router as printing_router
from baker.api.product_attributes import router as product_attributes_router
from baker.api.product_attribute_options import router as product_attribute_options_router
from baker.api.product_price_chips import router as product_price_chips_router
from baker.api.reconciliations import router as reconciliations_router
from baker.api.receipts import router as receipts_router
from baker.api.photos import router as photos_router
from baker.api.products import router as products_router
from baker.api.staff import router as staff_router
from baker.api.stock import router as stock_router
from baker.api.work_items import router as work_items_router
from baker.config import BUILD_FINGERPRINT, VERSION
from baker.db.connection import checkpoint_wal
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

    @app.on_event("shutdown")
    def _shutdown_wal_checkpoint():
        checkpoint_wal()

    # Register global exception handler
    app.add_exception_handler(Exception, global_exception_handler)

    # Logging middleware (added before CORS so it wraps all requests)
    app.add_middleware(LoggingMiddleware)

    # Tailscale network is air-gapped; only lily.tail10c2c6.ts.net is trusted
    app.add_middleware(
        CORSMiddleware,
        allow_origins=['https://lily.tail10c2c6.ts.net'],
        allow_credentials=True,
        allow_methods=['*'],
        allow_headers=[
            'Accept',
            'Accept-Language',
            'Content-Language',
            'Content-Type',
            'Authorization',
            'X-Requested-With',
            'x-device-model',
            'x-app-version',
            'x-os-version',
        ],
    )

    @app.get("/api/health")
    def health():
        return {"status": "ok", "version": VERSION, "fingerprint": BUILD_FINGERPRINT}

    app.include_router(photos_router)
    app.include_router(products_router)
    app.include_router(catalog_browse_router)
    app.include_router(catalog_router)
    app.include_router(categories_router)
    app.include_router(config_router)
    app.include_router(events_router)
    app.include_router(knowledge_router)
    app.include_router(orders_router)
    app.include_router(order_photos_router)
    app.include_router(work_items_router)
    app.include_router(payment_transactions_router)
    app.include_router(cake_queue_router)
    app.include_router(product_attributes_router)
    app.include_router(product_attribute_options_router)
    app.include_router(product_price_chips_router)
    app.include_router(staff_router)
    app.include_router(checklist_router)
    app.include_router(receipts_router)
    app.include_router(printing_router)
    app.include_router(stock_router)
    app.include_router(reconciliations_router)

    return app
