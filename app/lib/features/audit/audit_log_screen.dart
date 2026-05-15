import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/providers/supabase_provider.dart';

final _auditProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final sb = ref.watch(supabaseProvider);
  final rows = await sb
      .from('audit_log')
      .select('at, actor_id, action, target_tbl, target_id, ip')
      .order('at', ascending: false)
      .limit(200);
  return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

class AuditLogScreen extends ConsumerWidget {
  const AuditLogScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final m = ref.watch(membershipProvider);
    final rows = ref.watch(_auditProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Auditoría')),
      body: m.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (mem) {
          if (mem == null || mem.role != 'OWNER') {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                    'Solo el dueño de la clínica puede consultar la bitácora de auditoría.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.muted)),
              ),
            );
          }
          return rows.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (list) => ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final r = list[i];
                final ts = DateTime.tryParse(r['at'].toString())?.toLocal();
                return ListTile(
                  dense: true,
                  leading: Icon(
                    r['action'] == 'DELETE'
                        ? Icons.delete_outline
                        : (r['action'] == 'UPDATE'
                            ? Icons.edit_outlined
                            : Icons.add),
                    color: r['action'] == 'DELETE'
                        ? AppColors.danger
                        : AppColors.greenPrimary,
                  ),
                  title: Text('${r['action']} · ${r['target_tbl']}',
                      style: const TextStyle(
                          fontFamily: 'DMMono', fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${ts != null ? DateFormat('dd/MM HH:mm:ss').format(ts) : ''} · ${(r['actor_id']?.toString().substring(0, 8)) ?? '—'} · ${r['ip'] ?? ''}'),
                  trailing: Text(
                      r['target_id']?.toString().substring(0, 8) ?? '',
                      style: const TextStyle(fontFamily: 'DMMono', fontSize: 11)),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
