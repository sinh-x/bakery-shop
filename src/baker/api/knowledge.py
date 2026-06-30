"""Knowledge base API routes — CRUD + photo management."""

from fastapi import APIRouter, HTTPException, Query, UploadFile
from typing import Optional
from PIL import UnidentifiedImageError

from pydantic import BaseModel

from baker.db.connection import get_db
from baker.models.knowledge import Knowledge
from baker.api.photos import read_image_upload, save_photo
from baker.utils.time import now_utc

router = APIRouter(prefix="/api/knowledge", tags=["knowledge"])

VALID_TYPES = {"recipe", "procedure", "equipment", "supplier", "reference", "note"}


def _row_to_dict(row) -> dict:
    """Convert knowledge sqlite Row to a clean API dict."""
    d = dict(row)
    tags_str = d.get("tags") or ""
    d["tags"] = [t for t in tags_str.split(",") if t]
    if "pinned" in d:
        d["pinned"] = bool(d["pinned"])
    return d


def _fetch_photos(conn, entry_id: int) -> list[dict]:
    """Fetch photo records for a knowledge entry."""
    rows = conn.execute(
        """SELECT p.hash, p.original_name, kep.caption, kep.position
           FROM knowledge_entry_photos kep
           JOIN photos p ON p.id = kep.photo_id
           WHERE kep.entry_id = ?
           ORDER BY kep.position""",
        (entry_id,),
    ).fetchall()
    return [
        {
            "hash": r["hash"],
            "url": f"/api/photos/{r['hash']}.jpg",
            "caption": r["caption"] or "",
            "position": r["position"],
        }
        for r in rows
    ]


# ─── Request models ─────────────────────────────────────────────────────────────


class KnowledgeCreate(BaseModel):
    title: str
    content: str = ""
    type: str = "note"
    tags: list[str] = []
    logged_by: str = ""
    source: str = "app"


class KnowledgeUpdate(BaseModel):
    title: str | None = None
    content: str | None = None
    type: str | None = None
    tags: list[str] | None = None
    logged_by: str | None = None
    pinned: bool | None = None
    pinned_at: Optional[str] = None


# ─── Endpoints ────────────────────────────────────────────────────────────────────


@router.post("", status_code=201)
def create_knowledge(body: KnowledgeCreate):
    """Tạo mục tri thức mới."""
    if not body.title.strip():
        raise HTTPException(status_code=422, detail="title không được để trống")

    entry = Knowledge(
        title=body.title.strip(),
        content=body.content,
        type=body.type if body.type in VALID_TYPES else "note",
        tags=body.tags,
        logged_by=body.logged_by,
        source=body.source,
    )

    with get_db() as conn:
        entry_id = entry.save(conn)
        row = conn.execute(
            "SELECT * FROM knowledge_entries WHERE id = ?", (entry_id,)
        ).fetchone()
        result = _row_to_dict(row)
        result["photos"] = []
        return result


@router.get("")
def list_knowledge(
    type: str | None = Query(None, description="Lọc theo loại"),
    tag: str | None = Query(None, description="Lọc theo tag"),
    search: str | None = Query(None, description="Tìm trong tiêu đề và nội dung"),
    limit: int = Query(50, ge=1, le=500, description="Số kết quả tối đa"),
):
    """Danh sách mục tri thức với bộ lọc."""
    with get_db() as conn:
        conditions = ["1=1"]
        params: list = []

        if type:
            conditions.append("type = ?")
            params.append(type)

        if tag:
            conditions.append("tags LIKE ?")
            params.append(f"%{tag}%")

        if search:
            conditions.append("(title LIKE ? OR content LIKE ?)")
            params.append(f"%{search}%")
            params.append(f"%{search}%")

        query = f"""
            SELECT * FROM knowledge_entries
            WHERE {' AND '.join(conditions)}
            ORDER BY pinned DESC, CASE WHEN pinned = 1 THEN pinned_at ELSE updated_at END DESC
            LIMIT ?
        """
        params.append(limit)

        rows = conn.execute(query, params).fetchall()
        results = []
        for row in rows:
            d = _row_to_dict(row)
            d["photos"] = _fetch_photos(conn, row["id"])
            results.append(d)
        return results


@router.get("/{entry_id}")
def get_knowledge(entry_id: int):
    """Chi tiết một mục tri thức."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM knowledge_entries WHERE id = ?", (entry_id,)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy mục tri thức")
        result = _row_to_dict(row)
        result["photos"] = _fetch_photos(conn, entry_id)
        return result


@router.patch("/{entry_id}")
def update_knowledge(entry_id: int, body: KnowledgeUpdate):
    """Cập nhật mục tri thức (title, content, type, tags)."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM knowledge_entries WHERE id = ?", (entry_id,)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy mục tri thức")

        data = body.model_dump(exclude_unset=True)
        if not data:
            raise HTTPException(status_code=400, detail="Không có gì để cập nhật")

        fields: list[str] = []
        values: list = []

        if "title" in data:
            if not data["title"].strip():
                raise HTTPException(status_code=422, detail="title không được để trống")
            fields.append("title = ?")
            values.append(data["title"].strip())

        if "content" in data:
            fields.append("content = ?")
            values.append(data["content"])

        if "type" in data:
            fields.append("type = ?")
            values.append(data["type"] if data["type"] in VALID_TYPES else "note")

        if "tags" in data:
            fields.append("tags = ?")
            values.append(",".join(data["tags"]))

        if "logged_by" in data:
            fields.append("logged_by = ?")
            values.append(data["logged_by"])

        values.append(entry_id)
        conn.execute(
            f"UPDATE knowledge_entries SET {', '.join(fields)} WHERE id = ?",
            values,
        )

        row = conn.execute(
            "SELECT * FROM knowledge_entries WHERE id = ?", (entry_id,)
        ).fetchone()
        result = _row_to_dict(row)
        result["photos"] = _fetch_photos(conn, entry_id)
        return result


@router.delete("/{entry_id}")
def delete_knowledge(entry_id: int):
    """Xóa mục tri thức (cascade xóa ảnh qua FK)."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT id FROM knowledge_entries WHERE id = ?", (entry_id,)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy mục tri thức")

        conn.execute("DELETE FROM knowledge_entries WHERE id = ?", (entry_id,))
        return {"ok": True, "deleted": entry_id}


@router.post("/{entry_id}/pin")
def pin_knowledge(entry_id: int):
    """Ghim mục tri thức lên đầu danh sách."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT * FROM knowledge_entries WHERE id = ?", (entry_id,)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy mục tri thức")

        pinned_at = now_utc()
        conn.execute(
            "UPDATE knowledge_entries SET pinned = 1, pinned_at = ? WHERE id = ?",
            (pinned_at, entry_id),
        )

        row = conn.execute(
            "SELECT * FROM knowledge_entries WHERE id = ?", (entry_id,)
        ).fetchone()
        result = _row_to_dict(row)
        result["photos"] = _fetch_photos(conn, entry_id)
        return result


@router.delete("/{entry_id}/pin")
def unpin_knowledge(entry_id: int):
    """Bỏ ghim mục tri thức."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT id FROM knowledge_entries WHERE id = ?", (entry_id,)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy mục tri thức")

        conn.execute(
            "UPDATE knowledge_entries SET pinned = 0, pinned_at = NULL WHERE id = ?",
            (entry_id,),
        )

        row = conn.execute(
            "SELECT * FROM knowledge_entries WHERE id = ?", (entry_id,)
        ).fetchone()
        result = _row_to_dict(row)
        result["photos"] = _fetch_photos(conn, entry_id)
        return result


# ─── Photo management ──────────────────────────────────────────────────────────


@router.post("/{entry_id}/photos", status_code=201)
async def attach_photo(entry_id: int, file: UploadFile, caption: str = ""):
    """Đính kèm ảnh vào mục tri thức."""
    data = await read_image_upload(file)

    with get_db() as conn:
        # Verify entry exists
        row = conn.execute(
            "SELECT id FROM knowledge_entries WHERE id = ?", (entry_id,)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy mục tri thức")

        try:
            hash_hex = save_photo(data, file.filename or "")
        except (UnidentifiedImageError, OSError, ValueError):
            raise HTTPException(status_code=400, detail="Không thể xử lý hình ảnh")

        photo_row = conn.execute(
            "SELECT id FROM photos WHERE hash = ?", (hash_hex,)
        ).fetchone()
        photo_id = photo_row["id"]

        # Get max position
        pos_row = conn.execute(
            "SELECT COALESCE(MAX(position), -1) + 1 AS next_pos FROM knowledge_entry_photos WHERE entry_id = ?",
            (entry_id,),
        ).fetchone()
        next_pos = pos_row["next_pos"]

        conn.execute(
            """INSERT INTO knowledge_entry_photos (entry_id, photo_id, caption, position)
               VALUES (?, ?, ?, ?)""",
            (entry_id, photo_id, caption, next_pos),
        )

        return {
            "hash": hash_hex,
            "url": f"/api/photos/{hash_hex}.jpg",
            "caption": caption,
            "position": next_pos,
        }


@router.get("/{entry_id}/photos")
def list_photos(entry_id: int):
    """Danh sách ảnh đính kèm."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT id FROM knowledge_entries WHERE id = ?", (entry_id,)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy mục tri thức")
        return _fetch_photos(conn, entry_id)


@router.delete("/{entry_id}/photos/{photo_id}")
def detach_photo(entry_id: int, photo_id: int):
    """Xóa đính kèm ảnh (xóa junction, không xóa ảnh gốc)."""
    with get_db() as conn:
        row = conn.execute(
            "SELECT id FROM knowledge_entries WHERE id = ?", (entry_id,)
        ).fetchone()
        if not row:
            raise HTTPException(status_code=404, detail="Không tìm thấy mục tri thức")

        result = conn.execute(
            "DELETE FROM knowledge_entry_photos WHERE entry_id = ? AND photo_id = ?",
            (entry_id, photo_id),
        )
        if result.rowcount == 0:
            raise HTTPException(status_code=404, detail="Không tìm thấy ảnh đính kèm")
        return {"ok": True, "detached": photo_id}
