import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/message_template.dart';
import '../../../data/providers/template_providers.dart';
import '../../../shared/labels/templates.dart';
import '../../orders/widgets/section_header.dart';
import '../message_template_resolver.dart';
import '../template_context.dart';

/// Template picker modal (DG-375 Phase 4.3 / FR1, FR5, AC1, AC4, AC5).
///
/// A scrollable bottom sheet that shows message templates grouped by
/// scenario, with a live preview of the placeholder-filled text. Tapping a
/// template expands its preview; the "Sao chép" button copies the filled
/// text to the clipboard and shows a confirmation snackbar (FR5 / AC5).
///
/// The modal is opened with `showModalBottomSheet(isScrollControlled: true)`
/// from three integration points (AC1–AC3):
/// - Order detail screen overflow menu.
/// - Order create wizard overflow menu + review-stage button.
/// - Order edit wizard overflow menu + review-stage button.
///
/// Placeholder resolution uses [MessageTemplateResolver] with the
/// [TemplateContext] supplied by the caller. Empty fields render as
/// ``(trống)`` per the requirements doc.
class TemplatePickerModal extends ConsumerStatefulWidget {
  const TemplatePickerModal({
    super.key,
    required this.context,
    this.title,
  });

  /// The resolved order/wizard fields used to fill template placeholders.
  final TemplateContext context;

  /// Optional override for the modal title (defaults to the VN label).
  final String? title;

  /// Convenience method to open the modal as a scrollable bottom sheet.
  /// Returns a [Future] that completes when the sheet is dismissed.
  static Future<void> show(
    BuildContext context, {
    required TemplateContext templateContext,
    String? title,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => TemplatePickerModal(
        context: templateContext,
        title: title,
      ),
    );
  }

  @override
  ConsumerState<TemplatePickerModal> createState() =>
      _TemplatePickerModalState();
}

class _TemplatePickerModalState extends ConsumerState<TemplatePickerModal> {
  int? _expandedId;
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final templatesAsync = ref.watch(templateListProvider);
    final mediaQuery = MediaQuery.of(this.context);
    // Cap at ~85% of viewport so the sheet scrolls inside itself.
    final maxHeight = mediaQuery.size.height * 0.85;

    return SizedBox(
      height: maxHeight,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(theme),
            const SizedBox(height: 12),
            Expanded(
              child: templatesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _buildError(theme, e),
                data: (templates) {
                  if (templates.isEmpty) {
                    return _buildEmpty(theme);
                  }
                  return _buildList(theme, templates);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SectionHeader(widget.title ?? TemplatesLabels.pickerTitle),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: TemplatesLabels.closeLabel,
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ],
        ),
        Text(
          TemplatesLabels.pickerHint,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }

  Widget _buildError(ThemeData theme, Object error) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 40),
          const SizedBox(height: 8),
          Text(TemplatesLabels.emptyTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            '${VN.apiError}: $error',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.message_outlined, size: 40),
          const SizedBox(height: 8),
          Text(TemplatesLabels.emptyTitle, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            TemplatesLabels.emptyBody,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ThemeData theme, List<MessageTemplate> templates) {
    // Group by scenario preserving the backend's scenario, sort_order, id
    // ordering. Linked-iteration preserves insertion order.
    final grouped = <String, List<MessageTemplate>>{};
    for (final t in templates) {
      if (!t.active) continue;
      grouped.putIfAbsent(t.scenario, () => []).add(t);
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 6),
            child: Text(
              TemplatesLabels.scenarioLabel(entry.key),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final template in entry.value)
            _TemplateTile(
              template: template,
              templateContext: widget.context,
              expanded: _expandedId == template.id,
              copied: _copied && _expandedId == template.id,
              onTap: () => setState(() {
                _expandedId = _expandedId == template.id ? null : template.id;
                _copied = false;
              }),
              onCopy: () => _copyTemplate(template),
            ),
        ],
      ],
    );
  }

  Future<void> _copyTemplate(MessageTemplate template) async {
    final filled = MessageTemplateResolver(widget.context).resolveBody(template.body);
    await Clipboard.setData(ClipboardData(text: filled));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(TemplatesLabels.copiedSnack),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }
}

/// A single template row with expandable preview + copy button.
class _TemplateTile extends StatelessWidget {
  const _TemplateTile({
    required this.template,
    required this.templateContext,
    required this.expanded,
    required this.copied,
    required this.onTap,
    required this.onCopy,
  });

  final MessageTemplate template;
  final TemplateContext templateContext;
  final bool expanded;
  final bool copied;
  final VoidCallback onTap;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolver = MessageTemplateResolver(templateContext);
    final preview = resolver.resolveBody(template.body);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            template.name,
                            style: theme.textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        _Tag(isSystem: template.isSystem),
                      ],
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
              if (expanded) ...[
                const SizedBox(height: 8),
                Text(
                  TemplatesLabels.previewLabel,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      preview,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: onCopy,
                    icon: Icon(
                      copied ? Icons.check : Icons.copy,
                      size: 18,
                    ),
                    label: Text(
                      copied ? TemplatesLabels.copiedSnack : TemplatesLabels.copyButton,
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 4),
                Text(
                  preview.split('\n').first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.isSystem});
  final bool isSystem;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = isSystem ? TemplatesLabels.systemTag : TemplatesLabels.personalTag;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (isSystem
                ? theme.colorScheme.primaryContainer
                : theme.colorScheme.secondaryContainer)
            .withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: isSystem
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}