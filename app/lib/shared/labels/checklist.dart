export 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Checklist-domain Vietnamese labels for the bakery app.
///
/// Per the VN Label Policy in CLAUDE.md and §5 of
/// docs/flutter-coding-standards.md, new user-facing copy for the checklist
/// feature lives in its own domain file rather than being appended to the
/// monolithic `VN` class. Consumers import this file and use
/// `ChecklistLabels.*` for new labels or `VN.*` for legacy labels re-exported
/// above.
class ChecklistLabels {
  ChecklistLabels._();

  // Tab + screen titles
  static const tabChecklist = 'Checklist';
  static const packingChecklist = 'Danh sách đóng gói';

  // Packing items
  static const packCandles = 'Nến';
  static const packCutlery = 'Dao/dĩa';
  static const packBox = 'Hộp';
  static const packBase = 'Đế';
  static const packRibbon = 'Ruy-băng';

  // Knowledge base checklist subtitle
  static const knowledgeBaseChecklistSubtitle = 'Công việc mở / đóng tiệm';
}