"""Unit tests for _normalize_phone() and _pick_most_common_name() helpers.

Phase 1 of DG-204 — phone normalization + name dedup logic (FR2, FR3, AC2, AC3).
"""

import pytest

from baker.db.schema import _normalize_phone, _pick_most_common_name


# ---------------------------------------------------------------------------
# _normalize_phone
# ---------------------------------------------------------------------------


class Test_normalize_phone:
    def test_already_clean(self):
        assert _normalize_phone("84912345678") == "84912345678"

    @pytest.mark.parametrize(
        "phone, expected",
        [
            ("84 912 345 678", "84912345678"),
            ("84-912-345-678", "84912345678"),
            ("84.912.345.678", "84912345678"),
            ("84 912.345-678", "84912345678"),
            ("84 9 1 2 3 4 5 6 7 8", "84912345678"),
            ("8-4-9-1-2-3-4-5-6-7-8", "84912345678"),
            ("8.4.9.1.2.3.4.5.6.7.8", "84912345678"),
        ],
    )
    def test_separator_variants_all_collapse(self, phone, expected):
        # AC3: whitespace/dots/dashes all map to same canonical form
        assert _normalize_phone(phone) == expected

    def test_all_three_formats_produce_single_canonical(self):
        # AC3 explicit: three representations -> one canonical
        a = _normalize_phone("84912345678")
        b = _normalize_phone("84 912 345 678")
        c = _normalize_phone("84-912-345-678")
        assert a == b == c == "84912345678"

    def test_empty_string(self):
        assert _normalize_phone("") == ""

    def test_only_separators(self):
        assert _normalize_phone("   ") == ""
        assert _normalize_phone("---") == ""
        assert _normalize_phone("...") == ""
        assert _normalize_phone(" - . - . ") == ""

    def test_none_returns_empty(self):
        assert _normalize_phone(None) == ""

    def test_preserves_84_prefix(self):
        # No "+" stripping; 84 prefix stays
        assert _normalize_phone("84 0123 456 789") == "840123456789"

    def test_leading_trailing_spaces(self):
        assert _normalize_phone("  84912345678  ") == "84912345678"

    def test_internal_whitespace_runs(self):
        assert _normalize_phone("84    912    345    678") == "84912345678"

    def test_returns_str_for_str_input(self):
        assert isinstance(_normalize_phone("84912345678"), str)


# ---------------------------------------------------------------------------
# _pick_most_common_name
# ---------------------------------------------------------------------------


class Test_pick_most_common_name:
    def test_single_name(self):
        assert _pick_most_common_name(["Nguyen Van A"]) == "Nguyen Van A"

    def test_multiple_identical_names(self):
        assert _pick_most_common_name(["Bob", "Bob", "Bob"]) == "Bob"

    def test_most_frequent_wins(self):
        names = ["Nguyen Van A", "Bob", "Nguyen Van A", "Bob", "Nguyen Van A"]
        assert _pick_most_common_name(names) == "Nguyen Van A"

    def test_case_insensitive_matching(self):
        # AC2: "Nguyen Van A", "Nguyễn Văn A", "nguyen van a" — but for the
        # case-only variants (no diacritic distinction in FR3), "nguyen van a"
        # should be grouped with "Nguyen Van A".
        names = ["Nguyen Van A", "nguyen van a", "Bob", "Nguyen Van A"]
        assert _pick_most_common_name(names) == "Nguyen Van A"

    def test_whitespace_trimmed_for_comparison(self):
        names = ["  Nguyen Van A  ", "nguyen van a", "Bob", "Nguyen Van A"]
        assert _pick_most_common_name(names) == "Nguyen Van A"

    def test_preserves_original_casing_of_first_occurrence(self):
        # First occurrence of the winning (case-insensitive) group is returned
        names = ["nguyen van a", "Nguyen Van A", "Nguyen Van A"]
        assert _pick_most_common_name(names) == "nguyen van a"

    def test_tie_breaks_alphabetically(self):
        # Equal counts -> alphabetical (case-insensitive) wins
        names = ["Bob", "Alice"]
        assert _pick_most_common_name(names) == "Alice"

    def test_tie_breaks_alphabetically_case_insensitive(self):
        names = ["bob", "Alice", "bob", "Alice"]
        assert _pick_most_common_name(names) == "Alice"

    def test_empty_list(self):
        assert _pick_most_common_name([]) == ""

    def test_names_with_empty_strings(self):
        names = ["", "Bob", ""]
        # empty string normalized key "" has count 2, "bob" has count 1
        assert _pick_most_common_name(names) == ""

    def test_names_with_none_entries(self):
        names = [None, "Bob", None, "Bob"]
        # None normalizes to "" -> count 2; "bob" -> count 2; tie -> "" sorts first
        assert _pick_most_common_name(names) == ""

    def test_diacritic_variants_treated_as_distinct(self):
        # FR3 specifies case-insensitive + trim, NOT diacritic folding.
        # "Nguyễn Văn A" (with diacritics) is a different key from "Nguyen Van A".
        names = ["Nguyen Van A", "Nguyễn Văn A", "Nguyen Van A", "Nguyễn Văn A", "Bob"]
        # "nguyen van a" count 2, "nguyễn văn a" count 2, "bob" count 1
        # Tie between the two -> alphabetical: "nguyen van a" < "nguyễn văn a"
        assert _pick_most_common_name(names) == "Nguyen Van A"

    def test_large_group(self):
        names = ["A"] * 10 + ["B"] * 7 + ["C"] * 3
        assert _pick_most_common_name(names) == "A"

    def test_single_element_list(self):
        assert _pick_most_common_name(["Solo"]) == "Solo"

    def test_all_distinct_tie(self):
        names = ["Charlie", "Alpha", "Bravo"]
        assert _pick_most_common_name(names) == "Alpha"

    def test_returns_str(self):
        assert isinstance(_pick_most_common_name(["X"]), str)