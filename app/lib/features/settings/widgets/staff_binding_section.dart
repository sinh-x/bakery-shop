import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/events_provider.dart';
import '../../../providers/staff_provider.dart';
import '../../../providers/user_binding_provider.dart';
import '../../../shared/labels/shared.dart';
import '../../auth/auth_provider.dart';
import 'settings_sections.dart';

class StaffBindingSection extends ConsumerStatefulWidget {
  const StaffBindingSection({
    super.key,
    required this.auth,
    required this.manualNameCtrl,
  });

  final AuthState auth;
  final TextEditingController manualNameCtrl;

  @override
  ConsumerState<StaffBindingSection> createState() =>
      _StaffBindingSectionState();
}

class _StaffBindingSectionState extends ConsumerState<StaffBindingSection> {
  Future<void> _selectStaff(String name) async {
    await ref.read(loggedByProvider.notifier).setName(name);
    if (mounted) showTopSnackBar(context, VN.staffSaved);
  }

  Future<void> _saveManualName() async {
    final name = widget.manualNameCtrl.text.trim();
    if (name.isEmpty) return;
    await ref.read(loggedByProvider.notifier).setName(name);
    if (mounted) showTopSnackBar(context, VN.staffSaved);
  }

  Future<void> _selectBinding(int? staffId) async {
    final notifier = ref.read(staffBindingProvider.notifier);
    await notifier.updateBinding(staffId);
    if (mounted) {
      final newState = ref.read(staffBindingProvider);
      if (newState.hasError) {
        showTopSnackBar(
          context,
          VN.staffBindingSaveFailed,
          backgroundColor: Colors.red.shade800,
        );
        ref.invalidate(staffBindingProvider);
      } else {
        showTopSnackBar(context, VN.staffBindingSaved);
      }
    }
  }

  Widget _buildIdentityRow(AuthState auth) {
    final staffName = ref.watch(loggedByProvider);
    final bindingAsync = ref.watch(staffBindingProvider);
    final staffDisplay = bindingAsync.when(
      data: (b) => b.staffName ?? staffName,
      loading: () => staffName,
      error: (_, _) => staffName,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.person, size: 32),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(auth.username ?? '',
                    style: Theme.of(context).textTheme.titleMedium),
                if (staffDisplay.isNotEmpty)
                  Text(staffDisplay,
                      style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildStaffBindingSection() {
    final bindingAsync = ref.watch(staffBindingProvider);
    final staffAsync = ref.watch(staffListProvider);

    return [
      Text(VN.staffBindingTitle,
          style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 4),
      Text(
        VN.staffBindingHelp,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: Colors.grey),
      ),
      const SizedBox(height: 8),
      bindingAsync.when(
        data: (binding) => staffAsync.when(
          data: (staffList) => DropdownButtonFormField<int?>(
            initialValue: binding.staffId,
            hint: const Text(VN.staffBindingNone),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text(VN.staffBindingNone),
              ),
              ...staffList.map(
                (s) => DropdownMenuItem<int?>(
                  value: s.id,
                  child: Text(s.name),
                ),
              ),
            ],
            onChanged: (id) {
              if (id != binding.staffId) _selectBinding(id);
            },
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
          ),
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (_, _) => InkWell(
            onTap: () => ref.invalidate(staffBindingProvider),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                VN.staffBindingLoadError,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Colors.red),
              ),
            ),
          ),
        ),
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (_, _) => InkWell(
          onTap: () => ref.invalidate(staffBindingProvider),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              VN.staffBindingLoadError,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: Colors.red),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildGraceStaffPicker() {
    final staffAsync = ref.watch(staffListProvider);
    final currentStaff = ref.watch(loggedByProvider);

    return [
      Text(VN.staffPicker,
          style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      staffAsync.when(
        data: (staffList) => staffList.isEmpty
            ? ManualNameField(
                controller: widget.manualNameCtrl,
                onSave: _saveManualName,
              )
            : StaffDropdown(
                staffList: staffList.map((s) => s.name).toList(),
                selected: currentStaff.isNotEmpty ? currentStaff : null,
                onSelected: _selectStaff,
              ),
        loading: () => const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: CircularProgressIndicator(),
          ),
        ),
        error: (_, _) => ManualNameField(
          controller: widget.manualNameCtrl,
          onSave: _saveManualName,
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;

    return Column(
      children: [
        if (auth.isAuthenticated) ...[
          _buildIdentityRow(auth),
          const SizedBox(height: 16),
        ],
        if (auth.isAuthenticated && auth.isAdmin)
          ..._buildStaffBindingSection(),
        if (!auth.isAuthenticated) ..._buildGraceStaffPicker(),
      ],
    );
  }
}
