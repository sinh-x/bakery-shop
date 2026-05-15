// ignore_for_file: prefer_const_constructors  // DG-138#todo: replace with per-method suppressions after const audit
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

// Internal helper to track a photo (either existing or new local file)
class _PhotoEntry {
  _PhotoEntry({this.photo, this.file}) : assert(photo != null || file != null);
  final KnowledgePhoto? photo;
  final XFile? file;
}

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
  late String _selectedType;
  late final Set<String> _selectedTags;
  final _photos = <_PhotoEntry>[];
  bool _saving = false;
  bool _showTagField = false;
  bool _pinAfterSave = false;

  bool get _isEditing => widget.entry != null;

  String get _photoBaseUrl {
    final dio = ref.read(dioProvider);
    return dio.options.baseUrl;
  }

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _contentCtrl = TextEditingController(text: e?.content ?? '');
    _tagCtrl = TextEditingController();
    _selectedType = e?.type ?? 'note';
    _selectedTags = Set<String>.from(e?.tags ?? []);

    // Pre-fill existing photos as local entries
    if (e != null) {
      for (final photo in e.photos) {
        _photos.add(_PhotoEntry(photo: photo));
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    _tagCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    if (_photos.length >= 5) {
      showTopSnackBar(context, 'Tối đa 5 ảnh');
      return;
    }
    final picker = ImagePicker();
    final images = await picker.pickMultiImage();
    if (images.isNotEmpty) {
      if (!mounted) return;
      final remaining = 5 - _photos.length;
      setState(() {
        _photos.addAll(
          images.take(remaining).map((image) => _PhotoEntry(file: image)),
        );
      });
      if (images.length > remaining && mounted) {
        showTopSnackBar(context, 'Chỉ thêm được $remaining ảnh nữa');
      }
    }
  }

  void _confirmTag() {
    final tag = _tagCtrl.text.trim();
    if (tag.isNotEmpty) {
      setState(() {
        _selectedTags.add(tag);
        _tagCtrl.clear();
        _showTagField = false;
      });
    } else {
      setState(() => _showTagField = false);
    }
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final content = _contentCtrl.text.trim();
    if (title.isEmpty) return;

    setState(() => _saving = true);
    try {
      if (_isEditing) {
        await ref
            .read(knowledgeEntriesProvider.notifier)
            .updateEntry(
              widget.entry!.id,
              title: title,
              content: content,
              type: _selectedType,
              tags: _selectedTags.toList(),
            );
        // Upload new photos after update
        await _uploadNewPhotos(widget.entry!.id);
        ref.invalidate(knowledgeEntriesProvider);
        ref.invalidate(knowledgeEntryDetailProvider(widget.entry!.id));
        if (mounted) {
          showTopSnackBar(context, VN.knowledgeSaved);
          context.pop();
        }
      } else {
        final created = await ref
            .read(knowledgeEntriesProvider.notifier)
            .createEntry(
              title: title,
              content: content,
              type: _selectedType,
              tags: _selectedTags.toList(),
            );
        // Upload new photos after create
        await _uploadNewPhotos(created.id);
        ref.invalidate(knowledgeEntriesProvider);
        ref.invalidate(knowledgeEntryDetailProvider(created.id));
        // Pin after save if checked
        if (_pinAfterSave) {
          try {
            await ref
                .read(knowledgeEntriesProvider.notifier)
                .pinEntry(created.id, true);
          } catch (_) {}
        }
        if (mounted) {
          showTopSnackBar(context, VN.knowledgeCreated);
          context.pop();
        }
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, e.toString());
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? VN.editKnowledge : VN.createKnowledge),
        actions: [
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            tooltip: VN.save,
            onPressed: _saving ? null : _submit,
          ),
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
              labelText: VN.knowledgeTitleField,
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
              labelText: VN.knowledgeContentField,
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
              VN.knowledgeTypeField,
              style: theme.textTheme.titleSmall,
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _kTypeChips.map((t) {
              final selected = _selectedType == t.$1;
              return ChoiceChip(
                label: Text(t.$2),
                selected: selected,
                selectedColor: colorScheme.primaryContainer,
                onSelected: (_) => setState(() => _selectedType = t.$1),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Tags
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(VN.tagsLabel, style: theme.textTheme.titleSmall),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ..._selectedTags.map(
                (tag) => Chip(
                  label: Text(tag),
                  onDeleted: () => setState(() => _selectedTags.remove(tag)),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              if (_showTagField)
                SizedBox(
                  width: 120,
                  child: TextField(
                    controller: _tagCtrl,
                    autofocus: true,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      hintText: VN.addTag,
                      isDense: true,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
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
                  label: const Text(VN.addTag),
                  onPressed: () => setState(() => _showTagField = true),
                ),
            ],
          ),
          const SizedBox(height: 24),

          // Photos
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              VN.knowledgePhotosField,
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
                          VN.addPhoto,
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
                ..._photos.asMap().entries.map((mapEntry) {
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
                            onTap: () =>
                                setState(() => _photos.removeAt(index)),
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
          CheckboxListTile(
            value: _pinAfterSave,
            onChanged: (v) => setState(() => _pinAfterSave = v ?? false),
            title: const Text('Ghim sau khi lưu'),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Future<void> _uploadNewPhotos(int entryId) async {
    final newPhotos = _photos.where((p) => p.file != null).toList();
    if (newPhotos.isEmpty) return;
    final service = ref.read(knowledgeServiceProvider);
    var failed = 0;
    for (final photo in newPhotos) {
      try {
        final file = photo.file!;
        await service.attachPhoto(
          entryId,
          bytes: await file.readAsBytes(),
          filename: file.name,
        );
      } catch (_) {
        failed += 1;
      }
    }
    if (failed > 0) {
      throw Exception('Không thể tải lên $failed ảnh');
    }
  }

  ImageProvider _buildImage(_PhotoEntry photo) {
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
