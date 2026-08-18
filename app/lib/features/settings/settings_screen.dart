// DG-150 Phase 4 temporary exemption: screen coordinator remains above 300 lines until technical tab extraction can be isolated from connection side effects. DG-259 c6-fix (2026-07-19): staff binding section extracted, file now 333 lines.
import 'package:bakery_app/shared/utils.dart' show showTopSnackBar;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../data/api/api_client.dart';
import '../../shared/providers/auth_provider.dart';
import '../../shared/providers/logged_by_provider.dart';
import 'package:bakery_app/shared/labels/address_labels.dart';
import 'package:bakery_app/shared/labels/auth.dart';
import 'package:bakery_app/shared/labels/customers.dart';
import 'package:bakery_app/shared/labels/templates.dart';
import 'widgets/settings_sections.dart';
import 'widgets/staff_binding_section.dart';
import 'catalog_tags_settings_tab.dart';
import 'package:bakery_app/shared/labels/orders.dart';
import 'package:bakery_app/shared/labels/products.dart';
import 'package:bakery_app/shared/labels/shared.dart';
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Server URL section
  late TextEditingController _urlController;
  bool _testing = false;
  ConnectionResult? _testResult;

  // Staff section
  late TextEditingController _manualNameCtrl;

  // Version info
  String _appVersion = '';
  String _serverVersion = SharedLabels.serverVersionLoading;

  @override
  void initState() {
    super.initState();
    final auth = ref.read(authProvider);
    _isAdmin = auth.isAuthenticated && auth.isAdmin;
    _tabController = TabController(length: _isAdmin ? 4 : 3, vsync: this);
    _urlController = TextEditingController();
    _manualNameCtrl = TextEditingController();
    _loadAppVersion();
  }

  late final bool _isAdmin;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Pre-fill manual name from current logged-by value
    final currentName = ref.read(loggedByProvider);
    if (_manualNameCtrl.text.isEmpty && currentName.isNotEmpty) {
      _manualNameCtrl.text = currentName;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _urlController.dispose();
    _manualNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = '${info.version}+${info.buildNumber}';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _appVersion = '—');
    }
  }

  Future<void> _fetchServerVersion(String baseUrl) async {
    if (baseUrl.isEmpty) {
      setState(() => _serverVersion = SharedLabels.serverVersionError);
      return;
    }
    setState(() => _serverVersion = SharedLabels.serverVersionLoading);
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));
      final response = await dio.get('$baseUrl/api/health');
      if (mounted) {
        final data = response.data as Map<String, dynamic>?;
        setState(() {
          _serverVersion = (data?['version'] as String?) ?? '—';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _serverVersion = SharedLabels.serverVersionError);
    }
  }

  Future<void> _testConnection() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _testing = true;
      _testResult = null;
    });

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ));
      final response = await dio.get('$url/api/health');
      if (mounted) {
        final data = response.data as Map<String, dynamic>?;
        setState(() {
          _testing = false;
          _testResult = ConnectionResult(success: response.statusCode == 200);
          // Also update server version when test succeeds
          _serverVersion = (data?['version'] as String?) ?? '—';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _testing = false;
          _testResult = const ConnectionResult(success: false);
        });
      }
    }
  }

  Future<void> _saveUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      showTopSnackBar(context, SharedLabels.urlEmpty);
      return;
    }
    await ref.read(apiBaseUrlProvider.notifier).setUrl(url);
    if (mounted) {
      showTopSnackBar(context, SharedLabels.urlSaved);
      _fetchServerVersion(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUrl = ref.watch(apiBaseUrlProvider);
    final auth = ref.watch(authProvider);

    // Sync URL controller on first build
    if (_urlController.text.isEmpty && currentUrl.isNotEmpty) {
      _urlController.text = currentUrl;
      // Fetch server version when screen opens
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _fetchServerVersion(currentUrl);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(SharedLabels.settings),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(icon: Icon(Icons.person), text: SharedLabels.generalSettings),
            if (_isAdmin)
              const Tab(
                icon: Icon(Icons.settings),
                text: SharedLabels.technicalSettings,
              ),
            const Tab(icon: Icon(Icons.card_giftcard), text: OrdersLabels.extrasSettings),
            const Tab(
              icon: Icon(Icons.label_outline),
              text: ProductsLabels.catalogTagEditor,
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // ── Tab 1: Cài đặt chung ─────────────────────────────────
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (auth.isAuthenticated) ...[
                StaffBindingSection(auth: auth, manualNameCtrl: _manualNameCtrl),
                const SizedBox(height: 16),
                // Self-service password change (DG-319 Phase 5 / FR5 / AC5).
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: const Text(AuthLabels.changePasswordTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/change-password'),
                ),
                const SizedBox(height: 16),
                // Message template management (DG-375 Phase 4 / FR10).
                ListTile(
                  leading: const Icon(Icons.message_outlined),
                  title: const Text(TemplatesLabels.managementTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/templates/manage'),
                ),
                const SizedBox(height: 16),
                // Address library management (DG-385 Phase 5 / FR6/FR8/AC6).
                ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: const Text(AddressLabels.libraryNavEntry),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/addresses'),
                ),
                const SizedBox(height: 16),
                // Missing-links screen (DG-388 Phase 5 / FR5/AC6).
                // Full-screen route outside the shell, reachable from
                // Settings and from the Address Library screen.
                ListTile(
                  leading: const Icon(Icons.link_off),
                  title: const Text(AddressLabels.missingLinksNavEntry),
                  subtitle: const Text(AddressLabels.missingLinksNavSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/missing-links'),
                ),
                const SizedBox(height: 16),
                // Logout (DG-319 Phase 6 / FR6 / AC6).
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(AuthLabels.logout),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => ref.read(authProvider.notifier).logout(),
                ),
              ],
            ],
          ),

          // ── Tab 2: Kỹ thuật (admin-only, FR16/AC10) ─────────────
          if (_isAdmin)
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // App version
                InfoRow(
                  label: SharedLabels.appVersion,
                  value: _appVersion.isEmpty ? '...' : _appVersion,
                ),
                const SizedBox(height: 8),
                // Server version
                InfoRow(label: SharedLabels.serverVersion, value: _serverVersion),
                const SizedBox(height: 16),
                // Printer paper mode (DG-183 Phase 2)
                const PaperModeSection(),
                const SizedBox(height: 16),
                // Server URL
                Text(
                  SharedLabels.apiUrlLabel,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  SharedLabels.apiUrlHelp,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _urlController,
                  decoration: const InputDecoration(
                    hintText: SharedLabels.apiUrlHint,
                    prefixIcon: Icon(Icons.dns),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  onChanged: (_) {
                    if (_testResult != null) {
                      setState(() => _testResult = null);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _testing ? null : _testConnection,
                        icon: _testing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.wifi_find),
                        label: Text(_testing ? SharedLabels.testing : SharedLabels.testConnection),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _saveUrl,
                        icon: const Icon(Icons.save),
                        label: const Text(SharedLabels.save),
                      ),
                    ),
                  ],
                ),
                if (_testResult != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: _testResult!.success
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            _testResult!.success
                                ? Icons.check_circle
                                : Icons.error,
                            color: _testResult!.success
                                ? Colors.green
                                : Colors.red,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _testResult!.success
                                ? SharedLabels.connectionSuccess
                                : SharedLabels.connectionFailed,
                            style: TextStyle(
                              color: _testResult!.success
                                  ? Colors.green.shade800
                                  : Colors.red.shade800,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                // Audit log entry (admin-only — this tab is admin-gated).
                ListTile(
                  leading: const Icon(Icons.history_edu),
                  title: const Text(SharedLabels.openAuditLog),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/audit-log'),
                ),
                // Duplicate finder (admin-only — DG-252 Phase 7 — FR7/AC4).
                ListTile(
                  leading: const Icon(Icons.merge_type),
                  title: const Text(CustomersLabels.duplicateFinderTitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/customers/duplicates'),
                ),
              ],
            ),

          // ── Tab 3: Phụ kiện đi kèm ────────────────────────────────
          const ExtrasSettingsTab(),

          // ── Tab 4: Thẻ ảnh ────────────────────────────────────────
          const CatalogTagsSettingsTab(),
        ],
      ),
    );
  }
}
