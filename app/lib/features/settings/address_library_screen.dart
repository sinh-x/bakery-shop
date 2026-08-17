import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/address.dart';
import '../../../data/providers/address_library_provider.dart';
import '../../../shared/labels/address_labels.dart';
import '../../../shared/utils/launch_external_url.dart';

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
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(AddressLabels.libraryDeleteConfirmTitle),
            content: Text(AddressLabels.libraryDeleteConfirmBody
                .replaceAll('{address}', entry.displayAddress)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(VN.cancel),
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
          AddressLabels.libraryDeletedSnack
              .replaceAll('{address}', entry.displayAddress),
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
        error: (e, _) => _AddressLibraryErrorView(error: e),
        data: (entries) => entries.isEmpty
            ? _AddressLibraryEmptyView(
                hasSearch: _searchController.text.isNotEmpty,
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
                itemCount: entries.length,
                separatorBuilder: (_, _) =>
                    const Divider(height: 0, indent: 56),
                itemBuilder: (context, i) {
                  final entry = entries[i];
                  return _AddressLibraryRow(
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

/// One row of the address library list (FR6/AC6).
///
/// Renders the address as the title and an optional map-link icon +
/// truncated link as subtitle when [AddressLibraryEntry.googleMapsUrl]
/// is non-null. Edit and delete affordances are exposed via a trailing
/// row of icon buttons. When the entry has a stored Google Maps link,
/// an "Open in Google Maps" shortcut button (DG-388 Phase 5.6-c5 / FB-2)
/// launches the link via [launchExternalUrl], mirroring the
/// missing-links screen pattern.
class _AddressLibraryRow extends StatelessWidget {
  const _AddressLibraryRow({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  final AddressLibraryEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasLink = entry.googleMapsUrl != null &&
        entry.googleMapsUrl!.trim().isNotEmpty;
    return ListTile(
      leading: const Icon(Icons.location_on_outlined),
      title: Text(entry.displayAddress),
      subtitle: hasLink
          ? Row(
              children: [
                Icon(Icons.map_outlined,
                    size: 14, color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    entry.googleMapsUrl!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasLink)
            IconButton(
              icon: const Icon(Icons.open_in_new),
              tooltip: AddressLabels.libraryOpenMapTooltip,
              onPressed: () =>
                  launchExternalUrl(context, entry.googleMapsUrl),
            ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: AddressLabels.libraryEditTooltip,
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: AddressLabels.libraryDeleteTooltip,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

/// Empty-state view shown when the library has no entries (or no
/// matches for the current search). Distinguishes "no entries" from
/// "no matches" via [hasSearch] so the user knows whether to clear the
/// search or add a new entry.
class _AddressLibraryEmptyView extends StatelessWidget {
  const _AddressLibraryEmptyView({required this.hasSearch});

  final bool hasSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on_outlined, size: 40, color: Colors.grey),
            const SizedBox(height: 8),
            Text(
              hasSearch
                  ? AddressLabels.libraryNoMatches
                  : AddressLabels.libraryEmpty,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

/// Error view for the management screen. Offers a retry button that
/// re-fetches the library.
class _AddressLibraryErrorView extends ConsumerWidget {
  const _AddressLibraryErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text('${VN.apiError}: $error', textAlign: TextAlign.center),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => ref.read(addressLibraryProvider.notifier).refresh(),
            icon: const Icon(Icons.refresh),
            label: const Text(VN.retry),
          ),
        ],
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
  String? _addressError;
  String? _linkError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _addressController =
        TextEditingController(text: widget.initial?.displayAddress ?? '');
    _linkController =
        TextEditingController(text: widget.initial?.googleMapsUrl ?? '');
  }

  @override
  void dispose() {
    _addressController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.initial != null;

  /// Validate the form fields. Returns true if valid; sets the inline
  /// error state so the dialog re-renders with error text under each
  /// invalid field.
  bool _validate() {
    var ok = true;
    final address = _addressController.text.trim();
    if (address.isEmpty) {
      _addressError = AddressLabels.editorAddressRequired;
      ok = false;
    } else {
      _addressError = null;
    }
    final link = _linkController.text.trim();
    if (link.isNotEmpty) {
      final uri = Uri.tryParse(link);
      if (uri == null || !uri.hasScheme || !uri.host.contains('.')) {
        _linkError = AddressLabels.editorMapsLinkInvalid;
        ok = false;
      } else {
        _linkError = null;
      }
    } else {
      _linkError = null;
    }
    return ok;
  }

  Future<void> _save() async {
    if (!_validate()) {
      setState(() {});
      return;
    }
    setState(() {
      _saving = true;
    });
    final address = _addressController.text.trim();
    final link = _linkController.text.trim();
    final linkValue = link.isEmpty ? null : link;
    try {
      final notifier = ref.read(addressLibraryProvider.notifier);
      final AddressLibraryEntry result;
      if (_isEdit) {
        result = await notifier.updateEntry(
          widget.initial!.id,
          displayAddress: address,
          googleMapsUrl: linkValue,
        );
      } else {
        result = await notifier.createEntry(
          displayAddress: address,
          googleMapsUrl: linkValue,
        );
      }
      if (mounted) {
        setState(() => _saving = false);
        Navigator.of(context).pop(result);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          // Surface the backend error (e.g. 409 collision) under the
          // address field, since that's the most common conflict point.
          _addressError = AddressLabels.libraryErrorSnack;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                errorText: _addressError,
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
                errorText: _linkError,
                prefixIcon: const Icon(Icons.map_outlined),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text(VN.cancel),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text(VN.save),
        ),
      ],
    );
  }
}