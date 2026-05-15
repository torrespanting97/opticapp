import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/login_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/audit/audit_log_screen.dart';
import '../features/shell/main_shell.dart';
import '../features/orders/new_order_screen.dart';
import '../features/clients/clients_screen.dart';
import '../features/clients/client_detail_screen.dart';
import '../features/appointments/appointments_screen.dart';
import '../features/settings/calendar_settings_screen.dart';
import '../features/wallet/wallet_screen.dart';
import '../features/wallet/client_statement_screen.dart';
import '../features/map/coverage_map_screen.dart';
import '../features/scanner/scanner_screen.dart';
import '../features/stats/stats_screen.dart';
import '../features/prescriptions/report_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    redirect: (ctx, state) {
      final loggedIn = Supabase.instance.client.auth.currentSession != null;
      final atLogin  = state.matchedLocation == '/login';
      final atSignup = state.matchedLocation == '/signup';
      if (!loggedIn && !atLogin && !atSignup) return '/login';
      if (loggedIn && (atLogin || atSignup)) return '/';
      return null;
    },
    refreshListenable: GoRouterRefreshStream(
      Supabase.instance.client.auth.onAuthStateChange,
    ),
    routes: [
      GoRoute(path: '/login',  builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),

      // OAuth deep-link landing routes (no shell — shown as modal or redirect)
      GoRoute(
        path: '/oauth-success',
        builder: (_, __) => const _OAuthResultScreen(success: true),
      ),
      GoRoute(
        path: '/oauth-error',
        builder: (_, st) => _OAuthResultScreen(
          success: false,
          message: st.uri.queryParameters['msg'],
        ),
      ),

      ShellRoute(
        builder: (_, __, child) => MainShell(child: child),
        routes: [
          GoRoute(path: '/',             builder: (_, __) => const NewOrderScreen()),
          GoRoute(path: '/clients',      builder: (_, __) => const ClientsScreen()),
          GoRoute(
            path: '/clients/:id',
            builder: (_, st) => ClientDetailScreen(clientId: st.pathParameters['id']!),
          ),
          GoRoute(path: '/scanner',      builder: (_, __) => const ScannerScreen()),
          GoRoute(path: '/appointments', builder: (_, __) => const AppointmentsScreen()),
          GoRoute(path: '/wallet',       builder: (_, __) => const WalletScreen()),
          GoRoute(
            path: '/wallet/:clientId',
            builder: (_, st) => ClientStatementScreen(clientId: st.pathParameters['clientId']!),
          ),
          GoRoute(path: '/map',          builder: (_, __) => const CoverageMapScreen()),
          GoRoute(path: '/stats',        builder: (_, __) => const StatsScreen()),
          GoRoute(path: '/audit',        builder: (_, __) => const AuditLogScreen()),
          GoRoute(
            path: '/report/:orderId',
            builder: (_, st) => ReportScreen(orderId: st.pathParameters['orderId']!),
          ),
          GoRoute(
            path: '/settings/calendar',
            builder: (_, __) => const CalendarSettingsScreen(),
          ),
        ],
      ),
    ],
  );
});

// ── OAuth result screen ──────────────────────────────────────────────────
class _OAuthResultScreen extends StatelessWidget {
  const _OAuthResultScreen({required this.success, this.message});
  final bool success;
  final String? message;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Auto-navigate to calendar settings after short delay
      Future.delayed(const Duration(seconds: 2), () {
        if (context.mounted) context.go('/settings/calendar');
      });
    });

    return Scaffold(
      body: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            success ? Icons.check_circle_outline : Icons.error_outline,
            size: 64,
            color: success ? Colors.green : Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            success ? 'Calendario vinculado' : 'Error al vincular',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          if (!success && message != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          ],
          const SizedBox(height: 24),
          const CircularProgressIndicator(),
        ]),
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────

/// Adapts a Stream into a Listenable for GoRouter's refreshListenable.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.listen((_) => notifyListeners());
  }
  late final dynamic _sub;
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
