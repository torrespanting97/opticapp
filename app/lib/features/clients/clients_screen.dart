import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/repositories/clients_repo.dart';

class ClientsScreen extends ConsumerStatefulWidget {
  const ClientsScreen({super.key});
  @override
  ConsumerState<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends ConsumerState<ClientsScreen> {
  final _q = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final clients = ref.watch(clientsSearchProvider(_query));
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: TextField(
          controller: _q,
          onChanged: _onChanged,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: 'Buscar por nombre…',
            isDense: true,
          ),
        ),
      ),
      Expanded(
        child: clients.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (list) {
            if (list.isEmpty) {
              return const Center(
                child: Text('Sin resultados',
                    style: TextStyle(color: AppColors.muted)),
              );
            }
            return ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final c = list[i];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.greenSoft,
                    child: Text(
                      c.fullName.isNotEmpty ? c.fullName[0].toUpperCase() : '?',
                      style: const TextStyle(color: AppColors.greenPrimary, fontWeight: FontWeight.w800),
                    ),
                  ),
                  title: Text(c.fullName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([
                    if (c.phone != null) c.phone,
                    if (c.municipio != null) c.municipio,
                  ].whereType<String>().join(' · ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/clients/${c.id}'),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}
