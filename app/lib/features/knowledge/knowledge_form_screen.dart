// EXEMPT: 300-line threshold exceeded — pre-existing oversized file (was 436 lines before DG-333 Phase 8). Splitting form fields (title/content/type/tags/photos/pin) into sub-widgets now would duplicate controller ownership and save-flow wiring across widget boundaries. Phase 8 only replaced the inline upload loop with the shared notifier + indicator (+13 net). Reviewed 2026-08-02.
import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/api/api_client.dart';
import '../../data/api/knowledge_service.dart';
import '../../data/models/knowledge_entry.dart';
import '../../data/providers/knowledge_provider.dart';
import '../../providers/photo_upload_provider.dart';
import '../../shared/widgets/app_bar_overflow_menu.dart';
import '../../shared/widgets/upload_progress_indicator.dart';
import 'providers/knowledge_form_notifier.dart';
import '../../providers/form_draft_session_notifier.dart';
import '../../shared/models/form_draft_context.dart';
import '../../shared/widgets/discard_form_draft_action.dart';
import 'package:bakery_app/shared/labels/events.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'package:bakery_app/shared/labels/shared.dart';

// Knowledge types for the form
const _kTypeChips = [
  ('recipe', 'Công thức'),
  ('procedure', 'Quy trình'),
  ('equipment', 'Thiết bị'),
  ('supplier', 'Nhà cung cấp'),
  ('reference', 'Tham khảo'),
  ('note', 'Ghi chú'),
];

class KnowledgeFormScreen extends ConsumerStatefulWidget {
  const KnowledgeFormScreen({super.key, this.entry});

  /// If provided, editing existing entry; otherwise creating new.
  final KnowledgeEntry? entry;

  @override
  ConsumerState<KnowledgeFormScreen> createState() =>
      _KnowledgeFormScreenState();
}

class _KnowledgeFormScreenState extends ConsumerState<KnowledgeFormScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _contentCtrl;
  late final TextEditingController _tagCtrl;
  late final FormDraftContext _draftContext;

  NotifierProvider<KnowledgeFormNotifier, KnowledgeFormState> get _provider =>
      contextualKnowledgeFormProvider(_draftContext);

  bool get _isEditing => widget.entry != null;

  String get _photoBaseUrl {
    final dio = ref.read(dioProvider);
    return dio.options.baseUrl;
  }

  @override
  void initState() {
    super.initState();
    _draftContext = FormDraftContext(
      formType: 'knowledge',
      mode: _isEditing ? FormDraftMode.edit : FormDraftMode.create,
      entityId: widget.entry?.id.toString(),
    );
    // Clear any stale upload state from a previous screen navigation
    // (DG-333 Phase 5.6-c1-fix m2) so progress/errors don't leak across
    // screens that share the global photoUploadNotifierProvider. Deferred
    // to a microtask because Riverpod disallows provider mutation during
    // widget life-cycle hooks (initState/build).
    Future.microtask(
      () => ref.read(photoUploadNotifierProvider.notifier).reset(),
    );
    final e = widget.entry;
    final formNotifier = ref.read(_provider.notifier);
    final draft = formNotifier.newDraft;
    final restore = formNotifier.hasRetainedDraft;
    _titleCtrl = TextEditingController(
      text: restore ? draft.title : e?.title ?? '',
    );
    _contentCtrl = TextEditingController(
      text: restore ? draft.content : e?.content ?? '',
    );
    _tagCtrl = TextEditingController();
    _titleCtrl.addListener(_retainNewDraft);
    _contentCtrl.addListener(_retainNewDraft);
    // Defer provider mutations to a microtask because Riverpod disallows
    // provider mutation during widget life-cycle hooks (initState/build).
    Future.microtask(() {
      if (!mounted) return;
      ref.read(_provider.notifier).seed(e);
    });
  }

  void _retainNewDraft() {
    ref
        .read(_provider.notifier)
        .updateNewDraft(title: _titleCtrl.text, content: _contentCtrl.text);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final formState = ref.read(_provider);
    if (formState.photos.length >= 5) {
      showTopSnackBar(context, 'Tối đa 5 ảnh');
      return;
    }
    final picker = ImagePicker();
    final images = await picker.pickMultiImage();
    if (images.isNotEmpty) {
      if (!mounted) return;
      final remaining = 5 - ref.read(_provider).photos.length;
      ref
          .read(_provider.notifier)
          .addPhotos(
            images
                .take(remaining)
                .map((image) => KnowledgeFormPhotoEntry(file: image))
                .toList(),
          );
      if (images.length > remaining && mounted) {
        showTopSnackBar(context, 'Chỉ thêm được $remaining ảnh nữa');
      }
    }
  }

  void _confirmTag() {
    final tag = _tagCtrl.text.trim();
    if (tag.isNotEmpty) {
      ref.read(_provider.notifier).addTag(tag);
      _tagCtrl.clear();
    } else {
      ref.read(_provider.notifier).hideTagField();
    }
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty) return;

    final formNotifier = ref.read(_provider.notifier);
    final form = ref.read(_provider);
    final submittedDraft = formNotifier.draftSnapshot;
    final container = ProviderScope.containerOf(context, listen: false);
    final entriesNotifier = ref.read(knowledgeEntriesProvider.notifier);
    final photoService = ref.read(knowledgeServiceProvider);
    final upload = ref.read(photoUploadNotifierProvider.notifier);
    final newPhotos = form.photos.where((photo) => photo.file != null).toList();
    formNotifier.setSaving(true);
    try {
      if (_isEditing) {
        await entriesNotifier.updateEntry(
          widget.entry!.id,
          title: title,
          content: content,
          type: form.selectedType,
          tags: form.selectedTags.toList(),
        );
        // Upload new photos after update
        await _uploadNewPhotos(
          widget.entry!.id,
          newPhotos,
          photoService,
          upload,
          container,
        );
        container.invalidate(knowledgeEntriesProvider);
        container.invalidate(knowledgeEntryDetailProvider(widget.entry!.id));
        if (mounted) {
          showTopSnackBar(context, SharedLabels.knowledgeSaved);
          context.pop();
        }
      } else {
        final created = await entriesNotifier.createEntry(
          title: title,
          content: content,
          type: form.selectedType,
          tags: form.selectedTags.toList(),
        );
        // Upload new photos after create
        await _uploadNewPhotos(
          created.id,
          newPhotos,
          photoService,
          upload,
          container,
        );
        container.invalidate(knowledgeEntriesProvider);
        container.invalidate(knowledgeEntryDetailProvider(created.id));
        // Pin after save if checked
        if (form.pinAfterSave) {
          try {
            await entriesNotifier.pinEntry(created.id, true);
          } catch (_) {}
        }
        if (mounted) {
          showTopSnackBar(context, SharedLabels.knowledgeCreated);
          context.pop();
        }
      }
      formNotifier.clearAfterSuccess(submittedDraft);
    } catch (e) {
      if (mounted) {
        // Format the typed partial-failure exception's user-facing message
        // (DG-333 Phase 5.6-c1-fix m3); fall back to e.toString() for other
        // unexpected errors.
        final message = e is PhotoUploadPartialFailure
            ? SharedLabels.photoUploadCompleteWithErrors(
                e.completedCount,
                e.failedCount,
                e.totalCount,
              )
            : e.toString();
        showTopSnackBar(context, message);
      }
    } finally {
      formNotifier.setSaving(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final form = ref.watch(_provider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing
              ? SharedLabels.editKnowledge
              : SharedLabels.createKnowledge,
        ),
        actions: [
          DiscardFormDraftAction(
            isDirty: ref
                .watch(formDraftSessionProvider)
                .containsKey(_draftContext),
            onDiscard: () {
              ref.read(_provider.notifier).clearNewDraft();
              Navigator.of(context).pop();
            },
          ),
          IconButton(
            icon: form.saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            tooltip: SharedLabels.save,
            onPressed: form.saving ? null : _submit,
          ),
          const AppBarOverflowMenu(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Title
          TextField(
            controller: _titleCtrl,
            autofocus: !_isEditing,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: SharedLabels.knowledgeTitleField,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),

          // Content
          TextField(
            controller: _contentCtrl,
            minLines: 5,
            maxLines: 10,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: SharedLabels.knowledgeContentField,
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),

          // Type chips
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              SharedLabels.knowledgeTypeField,
              style: theme.textTheme.titleSmall,
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _kTypeChips.map((t) {
              final selected = form.selectedType == t.$1;
              return ChoiceChip(
                label: Text(t.$2),
                selected: selected,
                selectedColor: colorScheme.primaryContainer,
                onSelected: (_) =>
                    ref.read(_provider.notifier).setSelectedType(t.$1),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Tags
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              ProductsLabels.tagsLabel,
              style: theme.textTheme.titleSmall,
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ...form.selectedTags.map(
                (tag) => Chip(
                  label: Text(tag),
                  onDeleted: () => ref.read(_provider.notifier).removeTag(tag),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              if (form.showTagField)
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _tagCtrl,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      hintText: EventsLabels.addTag,
                      isDense: true,
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                    ),
                    onSubmitted: (_) => _confirmTag(),
                  ),
                )
              else
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text(EventsLabels.addTag),
                  onPressed: () => ref.read(_provider.notifier).showTagField(),
                ),
            ],
          ),
          const SizedBox(height: 24),

          // Photos
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              SharedLabels.knowledgePhotosField,
              style: theme.textTheme.titleSmall,
            ),
          ),
          SizedBox(
            height: 100,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                // Add photo button
                GestureDetector(
                  onTap: _pickPhoto,
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      border: Border.all(color: colorScheme.outline),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_a_photo, color: colorScheme.primary),
                        const SizedBox(height: 4),
                        Text(
                          SharedLabels.addPhoto,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Photo previews
                ...form.photos.asMap().entries.map((mapEntry) {
                  final index = mapEntry.key;
                  final photo = mapEntry.value;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            image: DecorationImage(
                              image: _buildImage(photo),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: GestureDetector(
                            onTap: () => ref
                                .read(_provider.notifier)
                                .removePhotoAt(index),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Per-photo upload progress / error states (FR1/FR2/FR4/AC10)
          UploadProgressIndicator(
            states: ref.watch(photoUploadNotifierProvider).states,
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: form.pinAfterSave,
            onChanged: (v) =>
                ref.read(_provider.notifier).setPinAfterSave(v ?? false),
            title: const Text('Ghim sau khi lưu'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Future<void> _uploadNewPhotos(
    int entryId,
    List<KnowledgeFormPhotoEntry> newPhotos,
    KnowledgeService service,
    PhotoUploadNotifier upload,
    ProviderContainer container,
  ) async {
    if (newPhotos.isEmpty) return;
    await upload.uploadAll(
      newPhotos.map((p) => p.file!).toList(growable: false),
      (file) async {
        final bytes = await file.readAsBytes();
        await service.attachPhoto(entryId, bytes: bytes, filename: file.name);
      },
    );
    final batch = container.read(photoUploadNotifierProvider);
    if (batch.hasErrors) {
      throw PhotoUploadPartialFailure(
        completedCount: batch.completedCount,
        failedCount: batch.failedCount,
        totalCount: batch.totalCount,
      );
    }
  }

  ImageProvider _buildImage(KnowledgeFormPhotoEntry photo) {
    if (photo.file != null) {
      if (kIsWeb) {
        return NetworkImage(photo.file!.path);
      }
      return FileImage(File(photo.file!.path));
    }
    // Existing photo — use API base URL + server-provided url path
    return NetworkImage('$_photoBaseUrl${photo.photo!.url}');
  }
}
