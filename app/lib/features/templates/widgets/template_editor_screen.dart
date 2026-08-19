import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/template_service.dart';
import '../../../data/models/message_template.dart';
import '../../../data/providers/template_providers.dart';
import '../../../shared/labels/templates.dart';
import '../providers/template_editor_notifier.dart';
import 'package:bakery_app/shared/labels/shared.dart';
/// Template editor screen (DG-375 Phase 4 / FR8, AC8).
///
/// A full-screen create/edit form for a single message template. The body
/// field has an "insert order field" helper ([_OrderFieldSheet]) that lists
/// the available placeholders (e.g. `{customer_name}`, `{order_code}`) and
/// inserts the selected placeholder at the cursor position (FR8 / AC8).
///
/// Admin callers may create system templates (`isSystem = true`); staff
/// callers create personal templates (`isSystem = false`). The backend
/// rejects a staff caller attempting to create a system template with 403,
/// so the [editorIsSystemLabel] toggle is only shown to admins.
class TemplateEditorScreen extends ConsumerStatefulWidget {
  const TemplateEditorScreen({
    super.key,
    this.template,
    this.initialIsSystem = false,
    this.isAdmin = false,
  });

  /// The template to edit. `null` = create mode.
  final MessageTemplate? template;

  /// Default `isSystem` value for create mode. Ignored in edit mode.
  final bool initialIsSystem;

  /// Whether the current caller is an admin (controls the system-template
  /// toggle visibility).
  final bool isAdmin;

  @override
  ConsumerState<TemplateEditorScreen> createState() =>
      _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends ConsumerState<TemplateEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _bodyCtrl;
  late final TextEditingController _cursorAccessor;

  bool get _isEditing => widget.template != null;

  @override
  void initState() {
    super.initState();
    final t = widget.template;
    _nameCtrl = TextEditingController(text: t?.name ?? '');
    _bodyCtrl = TextEditingController(text: t?.body ?? '');
    _cursorAccessor = TextEditingController();
    // Seed the editor notifier with the template (edit mode) or the
    // caller-supplied default isSystem flag (create mode).
    Future.microtask(() => ref
        .read(templateEditorProvider.notifier)
        .seed(widget.template, initialIsSystem: widget.initialIsSystem));
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bodyCtrl.dispose();
    _cursorAccessor.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    ref.read(templateEditorProvider.notifier).setSaving(true);
    final editor = ref.read(templateEditorProvider);
    final name = _nameCtrl.text.trim();
    try {
      final notifier = ref.read(templateListProvider.notifier);
      if (_isEditing) {
        await notifier.updateTemplate(
          widget.template!.id,
          scenario: editor.selectedScenario,
          name: name,
          body: _bodyCtrl.text,
          isSystem: editor.isSystem,
          active: editor.isActive,
        );
      } else {
        await notifier.createTemplate(
          scenario: editor.selectedScenario,
          name: name,
          body: _bodyCtrl.text,
          isSystem: editor.isSystem,
          active: editor.isActive,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
      showTopSnackBar(context, TemplatesLabels.editorSavedSnack.replaceAll('{name}', name));
    } catch (e) {
      if (mounted) {
        ref.read(templateEditorProvider.notifier).setSaving(false);
        showTopSnackBar(context, '${TemplatesLabels.editorSaveError} ($e)');
      }
    }
  }

  Future<void> _openOrderFieldSheet() async {
    final inserted = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => const _OrderFieldSheet(),
    );
    if (inserted == null || !mounted) return;
    _insertAtCursor('{$inserted}');
  }

  void _insertAtCursor(String snippet) {
    final controller = _bodyCtrl;
    final selection = controller.selection;
    final text = controller.text;
    if (!selection.isValid) {
      controller.text = text + snippet;
      controller.selection = TextSelection.collapsed(offset: text.length + snippet.length);
      return;
    }
    final newText = text.replaceRange(selection.start, selection.end, snippet);
    controller.text = newText;
    final newPos = selection.start + snippet.length;
    controller.selection = TextSelection.collapsed(offset: newPos);
  }

  @override
  Widget build(BuildContext context) {
    final editor = ref.watch(templateEditorProvider);
    final saving = editor.saving;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing
            ? TemplatesLabels.editorEditTitle
            : TemplatesLabels.editorCreateTitle),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameCtrl,
                autofocus: !_isEditing,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: TemplatesLabels.editorNameLabel,
                  hintText: TemplatesLabels.editorNameHint,
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? TemplatesLabels.editorNameRequired
                    : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: editor.selectedScenario,
                decoration: const InputDecoration(
                  labelText: TemplatesLabels.editorScenarioLabel,
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final slug in allowedTemplateScenarios)
                    DropdownMenuItem(
                      value: slug,
                      child: Text(TemplatesLabels.scenarioLabel(slug)),
                    ),
                ],
                onChanged: saving
                    ? null
                    : (v) => ref
                        .read(templateEditorProvider.notifier)
                        .setSelectedScenario(v ?? editor.selectedScenario),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bodyCtrl,
                maxLines: 8,
                minLines: 4,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: TemplatesLabels.editorBodyLabel,
                  hintText: TemplatesLabels.editorBodyHint,
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? TemplatesLabels.editorBodyRequired
                    : null,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: saving ? null : _openOrderFieldSheet,
                  icon: const Icon(Icons.data_object),
                  label: const Text(TemplatesLabels.editorInsertFieldButton),
                ),
              ),
              const SizedBox(height: 4),
              SwitchListTile.adaptive(
                title: const Text(TemplatesLabels.editorActiveLabel),
                subtitle: const Text(TemplatesLabels.editorActiveHint),
                value: editor.isActive,
                onChanged: saving
                    ? null
                    : (v) =>
                        ref.read(templateEditorProvider.notifier).setActive(v),
              ),
              if (widget.isAdmin) ...[
                SwitchListTile.adaptive(
                  title: const Text(TemplatesLabels.editorIsSystemLabel),
                  subtitle: const Text(TemplatesLabels.editorIsSystemHint),
                  value: editor.isSystem,
                  onChanged: saving
                      ? null
                      : (v) => ref
                          .read(templateEditorProvider.notifier)
                          .setIsSystem(v),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: saving ? null : () => Navigator.of(context).pop(),
                    child: const Text(SharedLabels.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: saving ? null : _save,
                    child: saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text(SharedLabels.save),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Insert order field" helper sheet (FR8 / AC8).
///
/// Lists the available placeholders from [TemplatesLabels.orderFieldPlaceholders].
/// Tapping a row returns the placeholder slug to the parent, which inserts it
/// as `{slug}` at the cursor position in the body text field.
class _OrderFieldSheet extends StatelessWidget {
  const _OrderFieldSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = TemplatesLabels.orderFieldPlaceholders.entries.toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              TemplatesLabels.editorInsertFieldTitle,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              TemplatesLabels.editorInsertFieldHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return ListTile(
                    leading: const Icon(Icons.data_object, size: 20),
                    title: Text('{${entry.key}}'),
                    subtitle: Text(entry.value),
                    dense: true,
                    onTap: () => Navigator.of(context).pop(entry.key),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}