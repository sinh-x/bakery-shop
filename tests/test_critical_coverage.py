"""Critical-coverage count guard (Phase 4.4 — NFR3/AC4).

Asserts that the count of tests tagged ``@pytest.mark.critical`` never drops
below the established baseline. The baseline is the count of critical-flow
tests (auth, payments, POS, migrations, accounting/reconciliation) tagged
during Phase 4.4 of the CI test strategy (DG-246). The guard prevents
accidental regression: removing a ``critical`` marker or deleting a critical
test file will trip this test and fail the fast gate (which runs
``-m "fast or critical"``) before the loss reaches production.

The count is derived at runtime by collecting the suite with
``-m critical`` so it stays accurate as new critical tests are added; the
hard floor below is the safety net.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

# Baseline established 2026-07-27 during Phase 4.4 of the CI test strategy
# (DG-246). The count is the number of tests collected with ``-m critical``
# immediately after tagging auth/payments/POS/migration files. Any increase
# is welcome; this floor only blocks decreases.
CRITICAL_COUNT_BASELINE = 910


def _count_critical_tests() -> int:
    """Run pytest collection with ``-m critical`` and parse the summary line.

    Uses a subprocess so the guard works regardless of how the outer pytest
    invocation was filtered (e.g. the fast gate runs ``-m "fast or critical"``
    but this guard must still measure the full critical set).
    """
    repo_root = Path(__file__).resolve().parents[1]
    result = subprocess.run(
        [
            sys.executable,
            "-m",
            "pytest",
            "tests",
            "--collect-only",
            "-q",
            "-m",
            "critical",
        ],
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
    )
    # pytest's --collect-only -q summary line looks like:
    #   "910/2171 tests collected (1261 deselected) in 7.65s"
    # When deselection occurs the format is "<n>/<total> tests collected
    # (<d> deselected) ...". When nothing is deselected it is just
    # "<n> tests collected ...". Parse the leading integer before the slash
    # or the first " tests collected" token.
    out = result.stdout
    for line in out.splitlines():
        stripped = line.strip()
        if "tests collected" in stripped:
            head = stripped.split(" tests collected", 1)[0]
            if "/" in head:
                head = head.split("/", 1)[0]
            try:
                return int(head)
            except ValueError:
                continue
    # Could not parse — fail loud so the baseline is fixed rather than silent.
    raise AssertionError(
        "Unable to parse critical test count from pytest collection output.\n"
        f"stdout:\n{out}\nstderr:\n{result.stderr}"
    )


@pytest.mark.critical
def test_critical_test_count_meets_baseline() -> None:
    """NFR3/AC4 — the critical-flow test set must not shrink below baseline.

    This guard itself is tagged ``critical`` so it runs in the fast gate and
    blocks any PR that removes a critical marker or deletes a critical test.
    """
    count = _count_critical_tests()
    assert count >= CRITICAL_COUNT_BASELINE, (
        f"Critical test count regression: {count} < baseline "
        f"{CRITICAL_COUNT_BASELINE}. A critical-flow test (auth/payments/"
        f"POS/migration) was removed or its `@pytest.mark.critical` marker "
        f"was dropped. Restore the marker or add a replacement critical test."
    )
