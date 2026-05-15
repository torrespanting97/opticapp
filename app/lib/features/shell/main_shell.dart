import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../data/outbox.dart';

class MainShell extends ConsumerWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  static const _items = [
    (label: 'Nueva',        icon: Icons.add_circle_outline, route: '/'),
    (label: 'Clientes',     icon: Icons.people_outline,     route: '/clients'),
    (label: 'Escáner IA',   icon: Icons.camera_alt_outlined, route: '/scanner'),
    (label: 'Citas',        icon: Icons.event_outlined,     route: '/appointments'),
    (label: 'Cartera',      icon: Icons.account_balance_wallet_outlined, route: '/wallet'),
    (label: 'Mapa',         icon: Icons.map_outlined,       route: '/map'),
    (label: 'Reportes',     icon: Icons.insights_outlined,  route: '/stats'),
  ];

  int _indexFromLocation(String loc) {
    final i = _items.indexWhere((it) => loc == it.route ||
        (it.route != '/' && loc.startsWith(it.route)));
    return i == -1 ? 0 : i;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = GoRouter.of(context).routerDelegate.currentConfiguration.uri.path;
    final idx = _indexFromLocation(loc);
    final isWide = MediaQuery.of(context).size.width >= 760 ||
        (!kIsWeb && (defaultTargetPlatform == TargetPlatform.windows ||
                     defaultTargetPlatform == TargetPlatform.macOS ||
                     defaultTargetPlatform == TargetPlatform.linux));

    if (isWide) {
      return Scaffold(
        appBar: _topBar(context, ref),
        body: Row(children: [
          NavigationRail(
            selectedIndex: idx,
            labelType: NavigationRailLabelType.all,
            backgroundColor: Colors.white,
            indicatorColor: AppColors.greenSoft,
            onDestinationSelected: (i) => context.go(_items[i].route),
            destinations: [
              for (final it in _items)
                NavigationRailDestination(
                  icon: Icon(it.icon),
                  label: Text(it.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ]),
      );
    }

    return Scaffold(
      appBar: _topBar(context, ref),
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx.clamp(0, _items.length - 1),
        onDestinationSelected: (i) => context.go(_items[i].route),
        destinations: [
          for (final it in _items.take(5))
            NavigationDestination(icon: Icon(it.icon), label: it.label),
        ],
      ),
    );
  }

  PreferredSizeWidget _topBar(BuildContext context, WidgetRef ref) {
    final outbox = ref.watch(outboxProvider);
    return AppBar(
      title: Row(children: const [
        Icon(Icons.visibility_outlined, size: 22),
        SizedBox(width: 8),
        Text('Salud Visual', style: TextStyle(fontWeight: FontWeight.w700)),
      ]),
      actions: [
        ValueListenableBuilder<int>(
          valueListenable: outbox.pendingCount,
          builder: (_, n, __) => n == 0
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Tooltip(
                    message: '$n cambios pendientes de sincronizar',
                    child: Chip(
                      avatar: const Icon(Icons.cloud_off,
                          color: Colors.white, size: 16),
                      label: Text('$n',
                          style: const TextStyle(color: Colors.white)),
                      backgroundColor: AppColors.amber,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
        ),
        IconButton(
          tooltip: 'Sincronizar ahora',
          onPressed: () async {
            final n = await outbox.flush();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(n == 0 ? 'Todo sincronizado.' : 'Subidos: $n')));
            }
          },
          icon: const Icon(Icons.sync),
        ),
        IconButton(
          tooltip: 'Cerrar sesión',
          onPressed: () => Supabase.instance.client.auth.signOut(),
          icon: const Icon(Icons.logout),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}

