"""Payment transaction API routes."""

import logging
from typing import Optional

from fastapi import APIRouter, HTTPException, Query, Request, UploadFile
from PIL import UnidentifiedImageError
from pydantic import BaseModel

from baker.api.auth import resolve_actor
from baker.api.photos import read_image_upload, save_photo
from baker.api.photos import SHA256_HEX_RE
from baker.db.connection import get_db
from baker.db.queries import paginate_params, paginated_envelope
from baker.models.payment_transaction import PaymentMethod, PaymentTransaction, TransactionType
from baker.models.payment_transaction_photo import PaymentTransactionPhoto
from baker.utils.time import now_utc

logger = logging.getLogger("baker.server")

router = APIRouter(prefix="/api/orders", tags=["payment-transactions"])


# NFR3: ``payment_source`` accepts absent, null, or empty string. Using
# ``Optional[str]`` (default ``""``) lets the API tolerate ``null`` payloads
# from clients that distinguish "unset" from "empty"; both normalize to "".
class TransactionCreate(BaseModel):
    amount: float
    type: str = "deposit"
    method: str = "cash"
    note: str = ""
    payment_source: Optional[str] = ""


class TransactionUpdate(BaseModel):
    amount: float | None = None
    type: str | None = None
    method: str | None = None
    note: str | None = None
    payment_source: Optional[str] = None


class InvalidationRequest(BaseModel):
    invalidatedBy: str = ""
    reason: str = ""


class TransactionPhotoLink(BaseModel):
    """Link an already-uploaded photo to a transaction by hash.

    Used by the record-payment flow where the photo has already been saved
    via ``/api/orders/{ref}/photos`` (order-level, tagged ``chuyen-khoan``)
    — this records the per-transaction edge (FR2) without re-uploading bytes.
    """

    photoHash: str


def _resolve_order_id(conn, ref: str) -> int:
    row = conn.execute(
        "SELECT id FROM orders WHERE order_ref = ? OR CAST(id AS TEXT) = ?",
        (ref, ref),
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy đơn hàng")
    return row["id"]


def _resolve_txn_or_404(conn, order_id: int, txn_id: int):
    """Return the payment_transactions row or raise 404.

    Used by the photo sub-routes so they share the same (order, txn)
    resolution semantics as the rest of the transaction endpoints.
    """
    row = conn.execute(
        "SELECT * FROM payment_transactions WHERE id = ? AND order_id = ?",
        (txn_id, order_id),
    ).fetchone()
    if not row:
        raise HTTPException(status_code=404, detail="Không tìm thấy giao dịch")
    return row


def _txn_photo_payload(conn, txn_id: int) -> Optional[dict]:
    """Build the API payload for a transaction's attached photo, or ``None``.

    Joins ``payment_transaction_photos`` with ``photos`` to surface the
    photo hash (used by the client to construct the ``/api/photos/{hash}.jpg``
    URL) alongside the link metadata. The shape mirrors
    :meth:`PaymentTransactionPhoto.to_api_dict` plus a ``photoHash`` field.
    """
    row = conn.execute(
        "SELECT ptp.*, ph.hash as photo_hash "
        "FROM payment_transaction_photos ptp "
        "LEFT JOIN photos ph ON ptp.photo_id = ph.id "
        "WHERE ptp.payment_transaction_id = ?",
        (txn_id,),
    ).fetchone()
    if not row:
        return None
    payload = PaymentTransactionPhoto.from_row(row).to_api_dict()
    payload["photoHash"] = row["photo_hash"] if "photo_hash" in row.keys() else None
    return payload


@router.get("/{ref}/transactions")
def list_transactions(
    ref: str,
    limit: int | None = Query(None, ge=1, le=500, description="Số lượng tối đa (mặc định 50)"),
    offset: int = Query(0, ge=0, description="Bỏ qua N giao dịch đầu"),
    paginated: bool = Query(False, description="Trả envelope {items,total,has_more} thay vì mảng trần (DG-409)"),
):
    """Danh sách giao dịch thanh toán của đơn hàng.

    Mặc định trả về mảng trần (backward-compatible, NFR6). Khi ``paginated=true``
    hoặc ``limit`` được cung cấp, trả về envelope ``{items, total, has_more,
    limit, offset}`` (FR14, DG-409 Phase 3).
    """
    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)
        base_sql = "SELECT * FROM payment_transactions WHERE order_id = ? ORDER BY id"
        use_envelope = paginated or limit is not None
        if use_envelope:
            lim, off = paginate_params(limit, offset)
            count_row = conn.execute(
                "SELECT COUNT(*) AS c FROM payment_transactions WHERE order_id = ?",
                (order_id,),
            ).fetchone()
            total = int(count_row["c"]) if count_row is not None else 0
            rows = conn.execute(
                base_sql + " LIMIT ? OFFSET ?",
                (order_id, lim, off),
            ).fetchall()
            items = [PaymentTransaction.from_row(r).to_api_dict() for r in rows]
            return paginated_envelope(items, total, lim, off)
        rows = conn.execute(base_sql, (order_id,)).fetchall()
        return [PaymentTransaction.from_row(r).to_api_dict() for r in rows]


@router.post("/{ref}/transactions", status_code=201)
def create_transaction(ref: str, body: TransactionCreate):
    """Tạo giao dịch thanh toán mới."""
    if body.amount <= 0:
        raise HTTPException(status_code=422, detail="Số tiền phải lớn hơn 0")

    valid_types = [t.value for t in TransactionType]
    if body.type not in valid_types:
        raise HTTPException(
            status_code=422,
            detail=f"Loại giao dịch không hợp lệ. Cho phép: {valid_types}",
        )

    valid_methods = [m.value for m in PaymentMethod]
    if body.method not in valid_methods:
        raise HTTPException(
            status_code=422,
            detail=f"Phương thức thanh toán không hợp lệ. Cho phép: {valid_methods}",
        )

    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)

        txn = PaymentTransaction(
            order_id=order_id,
            amount=body.amount,
            type=body.type,
            method=body.method,
            note=body.note,
            payment_source=body.payment_source or "",
        )
        txn.save(conn)

        # Auto-generate double-entry journal entry (DG-175).
        # Bus orders split the credit between Customer Deposits (2100) and
        # Bus Shipping Held (2200) — pass order_id so the journal sync reads
        # delivery_type/shipping_fee from the orders table (DG-191 Phase 2).
        # DG-244 Phase 4: payment_source routes the asset side to a distinct
        # bank sub-account (1210/1220) or the un-allocated fallback (1290).
        from baker.services.journal_sync import _sync_payment_journal, run_journal_sync, sync_status_to_warning
        sync_status = run_journal_sync(
            _sync_payment_journal,
            conn, txn.id, body.amount, body.type, body.method,
            order_id=order_id,
            payment_source=body.payment_source or "",
            log_label=f"payment journal sync for txn {txn.id}",
            source_type="payment_transaction",
            source_id=txn.id,
        )

        row = conn.execute(
            "SELECT * FROM payment_transactions WHERE id = ?", (txn.id,)
        ).fetchone()
        result = PaymentTransaction.from_row(row).to_api_dict()
        result["accountingSync"] = sync_status
        result["accountingSyncWarning"] = sync_status_to_warning(sync_status)
        return result


@router.patch("/{ref}/transactions/{txn_id}")
def update_transaction(ref: str, txn_id: int, body: TransactionUpdate):
    """Cập nhật giao dịch thanh toán."""
    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)
        row = conn.execute(
            "SELECT * FROM payment_transactions WHERE id = ? AND order_id = ?",
            (txn_id, order_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy giao dịch")

        txn = PaymentTransaction.from_row(row)

        if body.amount is not None:
            if body.amount <= 0:
                raise HTTPException(status_code=422, detail="Số tiền phải lớn hơn 0")
            txn.amount = body.amount
        if body.type is not None:
            valid_types = [t.value for t in TransactionType]
            if body.type not in valid_types:
                raise HTTPException(
                    status_code=422,
                    detail=f"Loại giao dịch không hợp lệ. Cho phép: {valid_types}",
                )
            txn.type = body.type
        if body.method is not None:
            valid_methods = [m.value for m in PaymentMethod]
            if body.method not in valid_methods:
                raise HTTPException(
                    status_code=422,
                    detail=f"Phương thức thanh toán không hợp lệ. Cho phép: {valid_methods}",
                )
            txn.method = body.method
        if body.note is not None:
            txn.note = body.note
        if body.payment_source is not None:
            txn.payment_source = body.payment_source or ""

        conn.execute(
            "UPDATE payment_transactions SET amount = ?, type = ?, method = ?, note = ?, payment_source = ? WHERE id = ?",
            (txn.amount, txn.type, txn.method, txn.note, txn.payment_source, txn.id),
        )

        # Re-sync double-entry journal entry (DG-175). Pass order_id so the
        # bus-shipping split is recomputed from the current delivery_type /
        # shipping_fee (DG-191 Phase 2). DG-244 Phase 4: payment_source
        # re-routes the asset side; an update on payment_source re-syncs the
        # journal entry to the correct bank sub-account.
        from baker.services.journal_sync import _sync_payment_journal, run_journal_sync, sync_status_to_warning
        sync_status = run_journal_sync(
            _sync_payment_journal,
            conn, txn.id, txn.amount, txn.type, txn.method,
            order_id=order_id,
            payment_source=txn.payment_source or "",
            log_label=f"payment journal re-sync for txn {txn.id}",
            source_type="payment_transaction",
            source_id=txn.id,
        )

        row = conn.execute(
            "SELECT * FROM payment_transactions WHERE id = ?", (txn.id,)
        ).fetchone()
        result = PaymentTransaction.from_row(row).to_api_dict()
        result["accountingSync"] = sync_status
        result["accountingSyncWarning"] = sync_status_to_warning(sync_status)
        return result


@router.delete("/{ref}/transactions/{txn_id}", status_code=204)
def delete_transaction(ref: str, txn_id: int):
    """Xóa giao dịch thanh toán."""
    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)
        row = conn.execute(
            "SELECT id, amount, type, method, payment_source FROM payment_transactions WHERE id = ? AND order_id = ?",
            (txn_id, order_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy giao dịch")
        payment_source = row["payment_source"] if "payment_source" in row.keys() else ""

        conn.execute("DELETE FROM payment_transactions WHERE id = ?", (txn_id,))

        # Reverse/delete the journal entry for the deleted transaction (DG-175).
        # Pass order_id so any bus-shipping held balance is consistent on
        # subsequent re-syncs (DG-191 Phase 2). No response body (204) — the
        # failure counter is surfaced via /api/health (OPS-1).
        # DG-244 Phase 4: payment_source is passed for API symmetry; the
        # deleted=True path reverses/deletes the existing entry directly
        # without re-resolving asset codes, so it is informational here.
        from baker.services.journal_sync import _sync_payment_journal, run_journal_sync
        run_journal_sync(
            _sync_payment_journal,
            conn, txn_id, float(row["amount"]), row["type"], row["method"],
            order_id=order_id, deleted=True,
            payment_source=payment_source or "",
            log_label=f"payment journal delete-sync for txn {txn_id}",
            source_type="payment_transaction",
            source_id=txn_id,
        )


def _now_iso() -> str:
    """Return the current UTC timestamp as an ISO-8601 string with Z suffix.

    All timestamps are UTC ``Z``-suffixed (DG-202 FR1) via
    :func:`baker.utils.time.now_utc`.
    """
    return now_utc()


@router.post("/{ref}/transactions/{txn_id}/invalidate")
def invalidate_transaction(ref: str, txn_id: int, body: InvalidationRequest, request: Request):
    """Đánh dấu giao dịch là không hợp lệ (soft-delete) + đảo bút toán journal.

    FR1/FR3: Sets ``invalidated_at``/``invalidated_by`` and reverses (locked)
    or deletes (unlocked) the matching journal entry via
    ``_sync_payment_journal(deleted=True)``. The locked-reversal path preserves
    the original ``transaction_date`` (same-timestamp reversal); the unlocked
    path deletes the entry outright. FR10: logs ``action_type='invalidate'`` to
    ``order_history``.
    """
    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)
        row = conn.execute(
            "SELECT * FROM payment_transactions WHERE id = ? AND order_id = ?",
            (txn_id, order_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy giao dịch")

        if row["invalidated_at"]:
            raise HTTPException(
                status_code=422,
                detail="Giao dịch đã được hủy trước đó",
            )

        invalidated_at = _now_iso()
        invalidated_by = resolve_actor(request, body.invalidatedBy)
        conn.execute(
            "UPDATE payment_transactions "
            "SET invalidated_at = ?, invalidated_by = ? WHERE id = ?",
            (invalidated_at, invalidated_by, txn_id),
        )

        # FR3/NFR2: journal sync is fire-and-forget. _sync_payment_journal
        # (deleted=True) reverses locked entries (preserving the original
        # transaction_date) and deletes unlocked ones.
        # DG-244 Phase 4: payment_source passed for symmetry (informational
        # on the deleted=True path which reverses/deletes the existing entry).
        payment_source = row["payment_source"] if "payment_source" in row.keys() else ""
        from baker.services.journal_sync import _sync_payment_journal, run_journal_sync, sync_status_to_warning
        sync_status = run_journal_sync(
            _sync_payment_journal,
            conn, txn_id, float(row["amount"]), row["type"], row["method"],
            order_id=order_id, deleted=True,
            payment_source=payment_source or "",
            log_label=f"payment journal invalidate-sync for txn {txn_id}",
            source_type="payment_transaction",
            source_id=txn_id,
        )

        # FR10: audit trail.
        try:
            from baker.api.orders import _log_order_history
            _log_order_history(
                conn, order_id, "invalidate", "payment_transaction",
                str(txn_id), invalidated_by, invalidated_by,
            )
        except Exception:
            logger.exception("order_history log failed for invalidate txn %d", txn_id)

        updated = conn.execute(
            "SELECT * FROM payment_transactions WHERE id = ?", (txn_id,)
        ).fetchone()
        result = PaymentTransaction.from_row(updated).to_api_dict()
        result["accountingSync"] = sync_status
        result["accountingSyncWarning"] = sync_status_to_warning(sync_status)
        return result


@router.post("/{ref}/transactions/{txn_id}/restore")
def restore_transaction(ref: str, txn_id: int):
    """Khôi phục giao dịch đã hủy + tạo lại bút toán journal.

    FR2/FR4: Clears ``invalidated_at``/``invalidated_by`` and re-creates the
    journal entry via ``_sync_payment_journal`` (create path), which uses the
    transaction's ``created_at`` as ``transaction_date`` (FR4). FR10: logs
    ``action_type='restore'`` to ``order_history``.
    """
    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)
        row = conn.execute(
            "SELECT * FROM payment_transactions WHERE id = ? AND order_id = ?",
            (txn_id, order_id),
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy giao dịch")

        if not row["invalidated_at"]:
            raise HTTPException(
                status_code=422,
                detail="Giao dịch chưa bị hủy, không cần khôi phục",
            )

        conn.execute(
            "UPDATE payment_transactions "
            "SET invalidated_at = NULL, invalidated_by = '' WHERE id = ?",
            (txn_id,),
        )

        # FR4/NFR2: journal sync is fire-and-forget. The create path reads the
        # transaction's created_at for transaction_date. If a prior reversal
        # entry exists (locked case), a new entry is created alongside it; the
        # reversal is left intact so the locked period's books are preserved.
        # DG-244 Phase 4: payment_source routes the asset side on restore.
        payment_source = row["payment_source"] if "payment_source" in row.keys() else ""
        from baker.services.journal_sync import _sync_payment_journal, run_journal_sync, sync_status_to_warning
        sync_status = run_journal_sync(
            _sync_payment_journal,
            conn, txn_id, float(row["amount"]), row["type"], row["method"],
            order_id=order_id,
            payment_source=payment_source or "",
            log_label=f"payment journal restore-sync for txn {txn_id}",
            source_type="payment_transaction",
            source_id=txn_id,
        )

        # FR10: audit trail.
        try:
            from baker.api.orders import _log_order_history
            _log_order_history(
                conn, order_id, "restore", "payment_transaction",
                str(txn_id), "", "",
            )
        except Exception:
            logger.exception("order_history log failed for restore txn %d", txn_id)

        updated = conn.execute(
            "SELECT * FROM payment_transactions WHERE id = ?", (txn_id,)
        ).fetchone()
        result = PaymentTransaction.from_row(updated).to_api_dict()
        result["accountingSync"] = sync_status
        result["accountingSyncWarning"] = sync_status_to_warning(sync_status)
        return result


# --- Transaction photo (DG-410 Phase 2) -----------------------------------
#
# FR1/FR3: a single photo may be linked to a transaction via the
# ``payment_transaction_photos`` join table (UNIQUE on
# payment_transaction_id). These routes wrap the Phase 1
# ``PaymentTransactionPhoto`` model so the record-payment / edit-payment /
# transaction-detail sheets can attach, replace, list, and detach the
# per-transaction photo. The order-level ``chuyen-khoan`` strip
# (``order_photos``) is unchanged (FR5).
#
# Reuse: ``save_photo`` / ``read_image_upload`` (NFR1 — 10 MB limit, hash
# dedup, flat storage) and the ``PaymentTransactionPhoto`` model (Phase 1).


@router.get("/{ref}/transactions/{txn_id}/photo")
def get_transaction_photo(ref: str, txn_id: int):
    """Lấy ảnh đính kèm của giao dịch (FR4 detail sheet).

    Returns the single attached photo link + hash, or ``404`` if no photo is
    attached. The client builds the image URL from ``photoHash`` via
    ``/api/photos/{hash}.jpg``.
    """
    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)
        _resolve_txn_or_404(conn, order_id, txn_id)
        payload = _txn_photo_payload(conn, txn_id)
        if payload is None:
            raise HTTPException(status_code=404, detail="Giao dịch chưa có ảnh")
        return payload


@router.post("/{ref}/transactions/{txn_id}/photo", status_code=201)
async def attach_transaction_photo(
    ref: str,
    txn_id: int,
    file: UploadFile,
):
    """Tải lên và đính kèm ảnh cho giao dịch (FR2 record / FR3 add/replace).

    Uploads the image bytes through ``save_photo`` (hash dedup, 10 MB limit,
    NFR1) and links the resulting photo to the transaction via
    ``PaymentTransactionPhoto.upsert_for_transaction`` — the UNIQUE
    constraint means re-attaching a different photo atomically replaces the
    existing link (FR3 replace).
    """
    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)
        _resolve_txn_or_404(conn, order_id, txn_id)

    data = await read_image_upload(file)

    try:
        hash_hex = save_photo(data, file.filename or "")
    except (UnidentifiedImageError, OSError, ValueError):
        logger.exception(
            "Transaction photo upload failed for txn %d, file: %s",
            txn_id, file.filename,
        )
        raise HTTPException(status_code=400, detail="Không thể xử lý hình ảnh")

    with get_db() as conn:
        photo_row = conn.execute(
            "SELECT id FROM photos WHERE hash = ?", (hash_hex,)
        ).fetchone()
        if not photo_row:
            raise HTTPException(status_code=500, detail="Lưu ảnh thất bại")
        photo_id = photo_row[0]

        link_id = PaymentTransactionPhoto.upsert_for_transaction(conn, txn_id, photo_id)
        conn.commit()

        payload = _txn_photo_payload(conn, txn_id)
        payload["id"] = str(link_id)
        return payload


@router.post("/{ref}/transactions/{txn_id}/photo/link", status_code=201)
def link_transaction_photo(ref: str, txn_id: int, body: TransactionPhotoLink):
    """Gắn ảnh đã tải lên sẵn cho giao dịch (FR2 record-payment flow).

    Links an already-saved photo (typically just uploaded to
    ``/api/orders/{ref}/photos`` as the order-level ``chuyen-khoan`` proof)
    to the newly-created transaction by hash — avoids a second upload of the
    same bytes. Uses ``upsert_for_transaction`` so a re-link replaces the
    existing edge (FR3 replace).

    SEC-1: the link is scoped to photos owned by the same order — the
    photo hash must (a) match ``SHA256_HEX_RE`` and (b) be referenced by an
    ``order_photos`` row for this order, so a caller cannot link another
    order's (or a knowledge-base/catalog) photo by guessing its hash.
    """
    if not SHA256_HEX_RE.fullmatch(body.photoHash):
        raise HTTPException(status_code=400, detail="Hash ảnh không hợp lệ")

    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)
        _resolve_txn_or_404(conn, order_id, txn_id)

        # Scope: the photo must be linked to the same order via order_photos.
        # The bare ``photos`` row alone is intentionally NOT sufficient — a
        # catalog/knowledge-base photo could otherwise be hijacked by hash.
        link_row = conn.execute(
            "SELECT p.id AS photo_id "
            "FROM photos p "
            "JOIN order_photos op ON op.photo_id = p.id "
            "WHERE p.hash = ? AND op.order_id = ?",
            (body.photoHash, order_id),
        ).fetchone()
        if not link_row:
            raise HTTPException(status_code=404, detail="Không tìm thấy ảnh")

        link_id = PaymentTransactionPhoto.upsert_for_transaction(
            conn, txn_id, int(link_row["photo_id"])
        )
        conn.commit()

        payload = _txn_photo_payload(conn, txn_id)
        payload["id"] = str(link_id)
        return payload


@router.delete("/{ref}/transactions/{txn_id}/photo", status_code=200)
def detach_transaction_photo(ref: str, txn_id: int):
    """Gỡ ảnh khỏi giao dịch (FR3 remove).

    Removes the per-transaction link row only; the underlying photo bytes
    and any ``order_photos`` references are untouched (FR5 — order-level
    strip stays unchanged). Returns ``200`` with a confirmation message.
    """
    with get_db() as conn:
        order_id = _resolve_order_id(conn, ref)
        _resolve_txn_or_404(conn, order_id, txn_id)

        deleted = PaymentTransactionPhoto.delete_for_transaction(conn, txn_id)
        conn.commit()

    if not deleted:
        raise HTTPException(status_code=404, detail="Giao dịch chưa có ảnh")
    return {"message": "Đã gỡ ảnh khỏi giao dịch"}
