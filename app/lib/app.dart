import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router.dart';
import 'core/security/idle_watcher.dart';
import 'core/theme.dart';
import 'main.dart' show initDeepLinkListener;

class SaludVisualApp extends ConsumerStatefulWidget {
  const SaludVisualApp({super.key});

  @override
  ConsumerState<SaludVisualApp> createState() => _SaludVisualAppState();
}

class _SaludVisualAppState extends ConsumerState<SaludVisualApp> {
  @override
  void initState() {
    super.initState();
    initDeepLinkListener(_handleDeepLink);
  }

  void _handleDeepLink(Uri uri) {
    if (uri.scheme != 'salud-visual') return;
    final router = ref.read(routerProvider);
    switch (uri.host) {
      case 'oauth-success':
        router.go('/oauth-success');
      case 'oauth-error':
        final msg = uri.queryParameters['msg'] ?? '';
        router.go('/oauth-error?msg=${Uri.encodeComponent(msg)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Salud Visual',
      theme: appTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) =>
          IdleWatcher(child: child ?? const SizedBox()),
    );
  }
}
