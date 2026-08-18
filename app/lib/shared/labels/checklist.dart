/// Checklist-domain Vietnamese labels for the bakery app.
///
/// Per the VN Label Policy in CLAUDE.md and §5 of
/// docs/flutter-coding-standards.md, user-facing copy for the checklist
/// feature lives in its own domain file rather than being appended to the
/// monolithic `VN` class. Consumers import this file and use
/// `ChecklistLabels.*` for new labels or `VN.*` for legacy labels still
/// re-exported via the per-domain label files.
class ChecklistLabels {
  ChecklistLabels._();

  // Navigation
  static const tabChecklist = 'Checklist';

  // Knowledge base entry subtitle
  static const knowledgeBaseChecklistSubtitle = 'Công việc mở / đóng tiệm';

  // Packing checklist (used on order detail screen)
  static const packingChecklist = 'Danh sách đóng gói';
}