import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/address.dart';
import '../../../data/providers/address_library_provider.dart';
import '../../../providers/form_draft_session_notifier.dart';
import '../../../shared/labels/address_labels.dart';
import 'package:bakery_app/shared/labels/shared.dart';
import '../../../shared/widgets/discard_form_draft_action.dart';
import 'providers/address_library_editor_notifier.dart';
import 'widgets/address_library_empty_view.dart';
import 'widgets/address_library_error_view.dart';
import 'widgets/address_library_row.dart';

/// Address-library management screen (DG-385 Phase 5 / FR6/FR8/AC6).
///
/// A full-screen management surface accessible from Settings. It lists
/// every entry in the address library, supports searching by address
/// text, and lets the user add, edit, or delete entries (FR6/AC6). CRUD
/// operations hit the Phase 2 backend endpoints
/// (`GET/POST/PATCH/DELETE /api/addresses/library`) through
/// [AddressService] and the [addressLibraryProvider] AsyncNotifier.
///
/// The screen follows the same structural pattern as the message-template
/// management screen (DG-375 Phase 4): a `Scaffold` with a search bar in
/// the AppBar, an `AsyncValue.when` body for loading/error/data, a FAB
/// for adding entries, and an in-place dialog for create/edit. Delete
/// goes through a confirmation dialog. Per NFR2 the screen is
/// platform-agnostic (Android, iOS, web) — no platform-specific plugins.
class AddressLibraryScreen extends ConsumerStatefulWidget {
  const AddressLibraryScreen({super.key});

  @override
  ConsumerState<AddressLibraryScreen> createState() =>
      _AddressLibraryScreenState();
}

class _AddressLibraryScreenState extends ConsumerState<AddressLibraryScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Submit the current search text to the provider (FR6/AC6 — "search by
  /// address text"). Trailing clear button is wired separately.
  Future<void> _onSearchSubmit(String value) async {
    await ref.read(addressLibraryProvider.notifier).search(value);
  }

  /// Clear the search and re-list all entries.
  Future<void> _clearSearch() async {
    _searchController.clear();
    await ref.read(addressLibraryProvider.notifier).search('');
  }

  Future<void> _openEditor({AddressLibraryEntry? entry}) async {
    final result = await showDialog<AddressLibraryEntry?>(
      context: context,
      builder: (_) => AddressLibraryEditorDialog(initial: entry),
    );
    if (!mounted) return;
    if (result == null) return;
    // Editor already wrote through the provider; nothing else to do.
    showTopSnackBar(
      context,
      entry == null
          ? AddressLabels.libraryCreatedSnack
          : AddressLabels.libraryUpdatedSnack,
    );
  }

  Future<void> _confirmDelete(AddressLibraryEntry entry) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(AddressLabels.libraryDeleteConfirmTitle),
            content: Text(
              AddressLabels.libraryDeleteConfirmBody.replaceAll(
                '{address}',
                entry.displayAddress,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(SharedLabels.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(AddressLabels.libraryDeleteConfirmAction),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    try {
      await ref.read(addressLibraryProvider.notifier).deleteEntry(entry.id);
      if (mounted) {
        showTopSnackBar(
          context,
          AddressLabels.libraryDeletedSnack.replaceAll(
            '{address}',
            entry.displayAddress,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showTopSnackBar(context, AddressLabels.libraryErrorSnack);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(addressLibraryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text(AddressLabels.libraryTitle),
        // Cross-link to the missing-links screen (DG-388 Phase 5 / FR5).
        // Lets staff jump directly from the address library to the list of
        // door-delivery addresses that still lack a Google Maps link.
        actions: [
          IconButton(
            icon: const Icon(Icons.link_off),
            tooltip: AddressLabels.missingLinksNavEntry,
            onPressed: () => context.push('/settings/missing-links'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: AddressLabels.librarySearchHint,
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _clearSearch,
                      )
                    : null,
              ),
              textInputAction: TextInputAction.search,
              onSubmitted: _onSearchSubmit,
            ),
          ),
        ),
      ),
      body: libraryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AddressLibraryErrorView(error: e),
        data: (entries) => entries.isEmpty
            ? AddressLibraryEmptyView(
                hasSearch: _searchController.text.isNotEmpty,
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
                itemCount: entries.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 0, indent: 56),
                itemBuilder: (context, i) {
                  final entry = entries[i];
                  return AddressLibraryRow(
                    entry: entry,
                    onEdit: () => _openEditor(entry: entry),
                    onDelete: () => _confirmDelete(entry),
                  );
                },
              ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: AddressLabels.libraryAddTooltip,
        onPressed: _openEditor,
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Create / edit dialog for an address library entry (FR8/AC6).
///
/// Mirrors the message-template editor pattern (DG-375 Phase 4): a
/// self-contained `AlertDialog` with two text fields (address + Google
/// Maps link), basic validation, and create-vs-update routing through
/// the [AddressLibraryNotifier]. Returns the persisted entry on
/// success so the caller can show a confirmation snackbar.
class AddressLibraryEditorDialog extends ConsumerStatefulWidget {
  const AddressLibraryEditorDialog({super.key, this.initial});

  /// The entry being edited, or null for create mode.
  final AddressLibraryEntry? initial;

  @override
  ConsumerState<AddressLibraryEditorDialog> createState() =>
      _AddressLibraryEditorDialogState();
}

class _AddressLibraryEditorDialogState
    extends ConsumerState<AddressLibraryEditorDialog> {
  late final TextEditingController _addressController;
  late final TextEditingController _linkController;
  late final _draftContext = addressLibraryEditorContext(widget.initial?.id);

  @override
  void initState() {
    super.initState();
    final notifier = ref.read(
      addressLibraryEditorProvider(_draftContext).notifier,
    );
    final draft = ref.read(addressLibraryEditorProvider(_draftContext));
    final restoreDraft = notifier.hasRetainedDraft;
    _addressController = TextEditingController(
      text: restoreDraft
          ? draft.address
          : (widget.initial?.displayAddress ?? draft.address),
    );
    _linkController = TextEditingController(
      text: restoreDraft
          ? draft.googleMapsUrl
          : (widget.initial?.googleMapsUrl ?? draft.googleMapsUrl),
    );
    _addressController.addListener(_persistDraft);
    _linkController.addListener(_persistDraft);
    Future.microtask(() {
      if (mounted) {
        ref
            .read(addressLibraryEditorProvider(_draftContext).notifier)
            .resetOperation();
      }
    });
  }

  bool get _isDirty =>
      _addressController.text != (widget.initial?.displayAddress ?? '') ||
      _linkController.text != (widget.initial?.googleMapsUrl ?? '');

  void _persistDraft() => ref
      .read(addressLibraryEditorProvider(_draftContext).notifier)
      .updateDraft(
        address: _addressController.text,
        googleMapsUrl: _linkController.text,
        isDirty: _isDirty,
      );

  @override
  void dispose() {
    _addressController.removeListener(_persistDraft);
    _linkController.removeListener(_persistDraft);
    _addressController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.initial != null;

  /// Validate the form fields. Returns true if valid; sets the inline
  /// error state via the notifier so the dialog re-renders with error
  /// text under each invalid field.
  bool _validate() {
    var ok = true;
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      ref
          .read(addressLibraryEditorProvider(_draftContext).notifier)
          .setAddressError(AddressLabels.editorAddressRequired);
      ok = false;
    } else {
      ref
          .read(addressLibraryEditorProvider(_draftContext).notifier)
          .setAddressError(null);
    }
    final link = _linkController.text.trim();
    if (link.isNotEmpty) {
      final uri = Uri.tryParse(link);
      if (uri == null || !uri.hasScheme || !uri.host.contains('.')) {
        ref
            .read(addressLibraryEditorProvider(_draftContext).notifier)
            .setLinkError(AddressLabels.editorMapsLinkInvalid);
        ok = false;
      } else {
        ref
            .read(addressLibraryEditorProvider(_draftContext).notifier)
            .setLinkError(null);
      }
    } else {
      ref
          .read(addressLibraryEditorProvider(_draftContext).notifier)
          .setLinkError(null);
    }
    return ok;
  }

  Future<void> _save() async {
    if (!_validate()) {
      return;
    }
    final formNotifier = ref.read(
      addressLibraryEditorProvider(_draftContext).notifier,
    );
    final registry = ref.read(formDraftSessionProvider.notifier);
    final submittedDraft =
        ref.read(formDraftSessionProvider)[_draftContext]
            as AddressLibraryEditorState?;
    final libraryNotifier = ref.read(addressLibraryProvider.notifier);
    formNotifier.setSaving(true);
    final address = _addressController.text.trim();
    final link = _linkController.text.trim();
    final linkValue = link.isEmpty ? null : link;
    try {
      final AddressLibraryEntry result;
      if (_isEdit) {
        result = await libraryNotifier.updateEntry(
          widget.initial!.id,
          displayAddress: address,
          googleMapsUrl: linkValue,
        );
      } else {
        result = await libraryNotifier.createEntry(
          displayAddress: address,
          googleMapsUrl: linkValue,
        );
      }
      if (submittedDraft != null) {
        registry.clearDraftIfUnchanged(_draftContext, submittedDraft);
      }
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } catch (_) {
      formNotifier.setAddressError(AddressLabels.libraryErrorSnack);
    } finally {
      formNotifier.setSaving(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final editorState = ref.watch(addressLibraryEditorProvider(_draftContext));
    return AlertDialog(
      title: Text(
        _isEdit
            ? AddressLabels.editorEditTitle
            : AddressLabels.editorCreateTitle,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _addressController,
              decoration: InputDecoration(
                labelText: AddressLabels.editorAddressLabel,
                hintText: AddressLabels.editorAddressHint,
                border: const OutlineInputBorder(),
                errorText: editorState.addressError,
              ),
              autofocus: !_isEdit,
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _linkController,
              decoration: InputDecoration(
                labelText: AddressLabels.editorMapsLinkLabel,
                hintText: AddressLabels.editorMapsLinkHint,
                border: const OutlineInputBorder(),
                errorText: editorState.linkError,
                prefixIcon: const Icon(Icons.map_outlined),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
          ],
        ),
      ),
      actions: [
        DiscardFormDraftAction(
          isDirty: _isDirty,
          onDiscard: () {
            ref
                .read(addressLibraryEditorProvider(_draftContext).notifier)
                .clear();
            _addressController.text = widget.initial?.displayAddress ?? '';
            _linkController.text = widget.initial?.googleMapsUrl ?? '';
          },
        ),
        TextButton(
          onPressed: editorState.saving
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text(SharedLabels.cancel),
        ),
        FilledButton(
          onPressed: editorState.saving ? null : _save,
          child: editorState.saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(SharedLabels.save),
        ),
      ],
    );
  }
}
