import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');

  await Supabase.initialize(
    url: Env.supabaseUrl,
    anonKey: Env.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(autoRefreshToken: true),
    realtimeClientOptions:
        const RealtimeClientOptions(logLevel: RealtimeLogLevel.info),
  );

  runApp(const ProviderScope(child: SaludVisualApp()));
}

/// Sets up the app_links deep link listener so that the OAuth callback
/// (`salud-visual://oauth-success` and `salud-visual://oauth-error`) is routed
/// through GoRouter. Call once from the root widget after the router is ready.
void initDeepLinkListener(void Function(Uri) onLink) {
  AppLinks().uriLinkStream.listen(onLink, onError: (_) {});
}
