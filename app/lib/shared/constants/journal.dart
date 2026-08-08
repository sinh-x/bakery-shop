/// Shared journal-related constants used across dashboard and Today Sales
/// providers (DG-374 Phase 5.6-c2-fix / C2-2).
///
/// Extracted from the duplicate `journalFetchPageSize` definitions that
/// existed in both `dashboard_metrics_provider.dart` and
/// `today_sales_provider.dart` so the two providers share a single source of
/// truth for the journal page size.
const int journalFetchPageSize = 500;
