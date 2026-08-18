import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/api/api_client.dart';
import '../../shared/labels/technical_settings.dart';
import 'widgets/settings_sections.dart';
import 'package:bakery_app/shared/widgets/vietnamese_labels.dart';

/// Factory that builds a standalone [Dio] instance for pre-login connection
/// tests (no auth interceptor). Overridable in tests via [preLoginDioFactoryProvider].
typedef DioFactory = Dio Function();

/// Default factory used in production — mirrors `settings_screen.dart`'s
/// `_testConnection()` standalone Dio (5s connect/receive timeout, no
/// interceptors).
Dio _defaultDioFactory() => Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ));

/// Provider exposing the connection-test Dio factory. Tests override this to
/// inject a mocked adapter without touching real network I/O.
final preLoginDioFactoryProvider =
    Provider<DioFactory>((ref) => _defaultDioFactory);

/// Pre-login technical settings screen (DG-367 Phase 2 / FR2 / FR3 / AC2 /
/// AC3 / AC6 / AC7).
///
/// Standalone screen (no tabs) reachable before login so users can configure
/// the server URL when the configured host is unreachable or on first device
/// setup. Reuses [ApiBaseUrlNotifier] for persistence and the connection-test
/// pattern from `settings_screen.dart` (standalone Dio, GET /api/health).
class PreLoginSettingsScreen extends ConsumerStatefulWidget {
  const PreLoginSettingsScreen({super.key});

  @override
  ConsumerState<PreLoginSettingsScreen> createState() =>
      _PreLoginSettingsScreenState();
}

class _PreLoginSettingsScreenState
    extends ConsumerState<PreLoginSettingsScreen> {
  late TextEditingController _urlController;
  bool _testing = false;
  ConnectionResult? _testResult;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final currentUrl = ref.read(apiBaseUrlProvider);
    if (_urlController.text.isEmpty && currentUrl.isNotEmpty) {
      _urlController.text = currentUrl;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _testing = true;
      _testResult = null;
    });

    try {
      final dio = ref.read(preLoginDioFactoryProvider)();
      final response = await dio.get<dynamic>('$url/api/health');
      if (mounted) {
        setState(() {
          _testing = false;
          _testResult = ConnectionResult(success: response.statusCode == 200);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _testing = false;
          _testResult = ConnectionResult(
            success: false,
            errorMessage: e.toString(),
          );
        });
      }
    }
  }

  Future<void> _saveUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      showTopSnackBar(context, TechnicalSettingsLabels.urlEmpty);
      return;
    }
    await ref.read(apiBaseUrlProvider.notifier).setUrl(url);
    if (mounted) {
      showTopSnackBar(context, TechnicalSettingsLabels.urlSaved);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => context.go('/login')),
        title: const Text(TechnicalSettingsLabels.screenTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            TechnicalSettingsLabels.serverUrlLabel,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            TechnicalSettingsLabels.serverUrlHelp,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(
              hintText: TechnicalSettingsLabels.serverUrlHint,
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
                  label: Text(_testing
                      ? TechnicalSettingsLabels.testing
                      : TechnicalSettingsLabels.testConnection),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saveUrl,
                  icon: const Icon(Icons.save),
                  label: const Text(TechnicalSettingsLabels.save),
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
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _testResult!.success
                                ? TechnicalSettingsLabels.connectionSuccess
                                : TechnicalSettingsLabels.connectionFailed,
                            style: TextStyle(
                              color: _testResult!.success
                                  ? Colors.green.shade800
                                  : Colors.red.shade800,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (!_testResult!.success &&
                              _testResult!.errorMessage != null)
                            Text(
                              _testResult!.errorMessage!,
                              style: TextStyle(
                                color: Colors.red.shade700,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}