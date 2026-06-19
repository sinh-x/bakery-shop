import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/api/paper_mode_service.dart';
import '../../../providers/paper_mode_provider.dart';
import '../../../shared/labels/shared.dart';

class ConnectionResult {
  const ConnectionResult({required this.success});

  final bool success;
}

class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label: ', style: Theme.of(context).textTheme.bodyMedium),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class StaffDropdown extends StatelessWidget {
  const StaffDropdown({
    super.key,
    required this.staffList,
    required this.selected,
    required this.onSelected,
  });

  final List<String> staffList;
  final String? selected;
  final Future<void> Function(String) onSelected;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: staffList.contains(selected) ? selected : null,
      hint: const Text(VN.staffPickerHint),
      items: staffList.map((name) => DropdownMenuItem(value: name, child: Text(name))).toList(),
      onChanged: (name) {
        if (name != null) onSelected(name);
      },
      decoration: const InputDecoration(
        border: OutlineInputBorder(),
        prefixIcon: Icon(Icons.person),
      ),
    );
  }
}

class ManualNameField extends StatelessWidget {
  const ManualNameField({super.key, required this.controller, required this.onSave});

  final TextEditingController controller;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: VN.staffNameManual,
              hintText: VN.staffNameHint,
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
            textCapitalization: TextCapitalization.words,
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(onPressed: onSave, child: const Text(VN.save)),
      ],
    );
  }
}

/// Printer paper mode dropdown (DG-183 Phase 2).
///
/// Loads the effective paper mode from the print status API and persists
/// selections to `app_config.paper_mode`. Selection takes effect on the next
/// print/status call — no server restart required (NFR2).
class PaperModeSection extends ConsumerStatefulWidget {
  const PaperModeSection({super.key});

  @override
  ConsumerState<PaperModeSection> createState() => _PaperModeSectionState();
}

class _PaperModeSectionState extends ConsumerState<PaperModeSection> {
  String? _paperModeLabel(String mode) {
    switch (mode) {
      case 'label':
        return VN.paperModeLabelOption;
      case 'roll':
        return VN.paperModeRollOption;
      default:
        return null;
    }
  }

  Future<void> _onSelected(String mode) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(paperModeProvider.notifier).setMode(mode);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(VN.paperModeSaved),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(VN.paperModeSaveFailed),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final paperModeAsync = ref.watch(paperModeProvider);
    return paperModeAsync.when(
      data: (mode) => _PaperModeDropdown(
        selected: paperModes.contains(mode) ? mode : null,
        optionLabel: _paperModeLabel,
        onSelected: _onSelected,
      ),
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(VN.paperModeLabel, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            VN.paperModeLoadError,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.red),
          ),
        ],
      ),
    );
  }
}

class _PaperModeDropdown extends StatelessWidget {
  const _PaperModeDropdown({
    required this.selected,
    required this.optionLabel,
    required this.onSelected,
  });

  final String? selected;
  final String? Function(String) optionLabel;
  final Future<void> Function(String) onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(VN.paperModeLabel, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          VN.paperModeHelp,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: selected,
          hint: const Text(VN.paperModeLabel),
          items: paperModes
              .map(
                (mode) => DropdownMenuItem(
                  value: mode,
                  child: Text(optionLabel(mode) ?? mode),
                ),
              )
              .toList(),
          onChanged: (mode) {
            if (mode != null) onSelected(mode);
          },
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.print),
          ),
        ),
      ],
    );
  }
}

class ExtrasSettingsTab extends ConsumerStatefulWidget {
  const ExtrasSettingsTab({super.key});

  @override
  ConsumerState<ExtrasSettingsTab> createState() => _ExtrasSettingsTabState();
}

class _ExtrasSettingsTabState extends ConsumerState<ExtrasSettingsTab> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.info_outline),
                    title: Text(VN.extrasSettingsDeprecatedTitle),
                    subtitle: Text(VN.extrasSettingsDeprecatedBody),
                  ),
                  SizedBox(height: 8),
                  Text(VN.extrasSettingsDeprecatedAction),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
