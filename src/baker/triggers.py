"""Log trigger evaluation engine — fires actions (e.g., Zalo) on matching log entries."""

import json
import logging
import subprocess
from datetime import datetime, timedelta

from baker.db.connection import get_db

logger = logging.getLogger("baker.server")


def _matches_condition(entry: dict, condition: dict) -> bool:
    """Check if a log entry matches a trigger condition."""
    if "level" in condition and entry.get("level") != condition["level"]:
        return False
    if "path_pattern" in condition:
        pattern = condition["path_pattern"]
        path = entry.get("path", "")
        if pattern.endswith("*"):
            if not path.startswith(pattern[:-1]):
                return False
        elif path != pattern:
            return False
    if "status_code" in condition and entry.get("status_code") != condition["status_code"]:
        return False
    if "min_status" in condition and entry.get("status_code", 0) < condition["min_status"]:
        return False
    return True


def _fire_action(action: dict, entry: dict) -> None:
    """Execute a trigger action."""
    action_type = action.get("type", "")
    if action_type == "zalo":
        group = action.get("group", "Thảnh thơi")
        template = action.get("template", "[Baker] {level}: {method} {path} → {status_code}")
        msg = template.format(**entry)
        try:
            subprocess.Popen(
                ["zca-send", "--to", group, "--msg", msg, "--group"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except FileNotFoundError:
            logger.warning("zca-send not found — cannot fire Zalo trigger")
        except Exception:
            logger.warning("Failed to fire Zalo trigger", exc_info=True)
    elif action_type == "log":
        logger.info("Trigger fired: %s", entry.get("message", ""))


def evaluate_triggers(entry: dict) -> None:
    """Evaluate all active triggers against a log entry."""
    try:
        with get_db() as conn:
            rows = conn.execute(
                "SELECT * FROM log_triggers WHERE active = 1"
            ).fetchall()

            now = datetime.now()
            for row in rows:
                try:
                    condition = json.loads(row["condition"])
                    action = json.loads(row["action"])
                except (json.JSONDecodeError, TypeError):
                    continue

                if not _matches_condition(entry, condition):
                    continue

                # Check cooldown
                cooldown = row["cooldown_seconds"] or 300
                last_fired = row["last_fired"]
                if last_fired:
                    try:
                        last_dt = datetime.fromisoformat(last_fired)
                        if now - last_dt < timedelta(seconds=cooldown):
                            continue
                    except (ValueError, TypeError):
                        pass

                # Fire and update last_fired
                _fire_action(action, entry)
                conn.execute(
                    "UPDATE log_triggers SET last_fired = ? WHERE id = ?",
                    (now.isoformat(), row["id"]),
                )
    except Exception:
        logger.warning("Trigger evaluation error", exc_info=True)
