import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/providers/fingerprint_provider.dart';
import 'shared/build_fingerprint.dart';
import 'shared/router/app_router.dart';
import 'shared/theme/bakery_theme.dart';
import 'package:bakery_app/shared/labels/shared.dart';

class BakeryApp extends ConsumerWidget {
  const BakeryApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final comparisonAsync = ref.watch(fingerprintComparisonProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: VN.appName,
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: BakeryTheme.light(),
      darkTheme: BakeryTheme.dark(),
      routerConfig: router,
      builder: (context, child) {
        final comparison = comparisonAsync.asData?.value;
        final warningState = comparison?.state;
        final dismissed = ref.watch(fingerprintWarningDismissedProvider);
        final showWarning = !dismissed && (
            warningState == FingerprintComparisonState.mismatch ||
            warningState == FingerprintComparisonState.serverUnknown);

        if (!showWarning) {
          return child ?? const SizedBox.shrink();
        }

        return Column(
          children: [
            _FingerprintWarningStrip(comparison: comparison!),
            Expanded(child: child ?? const SizedBox.shrink()),
          ],
        );
      },
    );
  }
}

class _FingerprintWarningStrip extends ConsumerWidget {
  const _FingerprintWarningStrip({required this.comparison});

  final FingerprintComparison comparison;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ColoredBox(
      color: colorScheme.errorContainer,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 18, color: colorScheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    comparison.state == FingerprintComparisonState.serverUnknown
                        ? VN.serverFingerprintUnavailableWarning
                        : VN.fingerprintMismatchStrip(
                            shortBuildFingerprint(comparison.clientFingerprint),
                            shortBuildFingerprint(comparison.serverFingerprint),
                          ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => ref.read(fingerprintWarningDismissedProvider.notifier).dismiss(),
                  child: Padding(
                    padding: const EdgeInsets.all(11),
                    child: Icon(Icons.close, size: 18, color: colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
