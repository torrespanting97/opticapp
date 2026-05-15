import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/security/form_v.dart';
import '../../core/theme.dart';
import '../../data/providers/supabase_provider.dart';
import '../../data/repositories/clients_repo.dart';
import '../../data/repositories/wallet_repo.dart';

final _money = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

class ClientStatementScreen extends ConsumerWidget {
  final String clientId;
  const ClientStatementScreen({super.key, required this.clientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(clientByIdProvider(clientId));
    final ledger = ref.watch(ledgerProvider(clientId));
    final balance = ledger.maybeWhen(
        data: (rows) => rows.fold<double>(0, (s, r) {
              final signed = r.kind == 'PAYMENT' ? -r.amount : r.amount;
              return s + signed;
            }),
        orElse: () => 0.0);
    return Scaffold(
      appBar: AppBar(
        title: client.maybeWhen(
          data: (c) => Text('Cartera · ${c?.fullName ?? ''}'),
          orElse: () => const Text('Cartera'),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addPayment(context, ref),
        icon: const Icon(Icons.payments_outlined),
        label: const Text('Registrar pago'),
      ),
      body: Column(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: balance > 0 ? Colors.red.shade50 : AppColors.greenSoft,
          child: Column(children: [
            const Text('Saldo actual',
                style: TextStyle(color: AppColors.muted, fontSize: 11)),
            const SizedBox(height: 4),
            Text(_money.format(balance),
                style: TextStyle(
                  fontFamily: 'DMMono',
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: balance > 0 ? AppColors.danger : AppColors.greenPrimary,
                )),
          ]),
        ),
        Expanded(
          child: ledger.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (rows) => rows.isEmpty
                ? const Center(
                    child: Text('Sin movimientos',
                        style: TextStyle(color: AppColors.muted)))
                : ListView.separated(
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final r = rows[i];
                      final isCharge = r.kind == 'CHARGE';
                      return ListTile(
                        leading: Icon(
                          isCharge ? Icons.arrow_upward : Icons.arrow_downward,
                          color: isCharge ? AppColors.danger : AppColors.greenPrimary,
                        ),
                        title: Text(r.kind,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            '${DateFormat('dd/MM/yyyy HH:mm').format(r.entryDate.toLocal())}${r.note != null ? ' · ${r.note}' : ''}'),
                        trailing: Text(
                          (isCharge ? '+' : '-') + _money.format(r.amount),
                          style: TextStyle(
                            fontFamily: 'DMMono',
                            fontWeight: FontWeight.w800,
                            color: isCharge ? AppColors.danger : AppColors.greenPrimary,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }

  Future<void> _addPayment(BuildContext context, WidgetRef ref) async {
    final amount = TextEditingController();
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Registrar pago'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(
            controller: amount,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Monto *'),
            autofocus: true,
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: note,
            decoration: const InputDecoration(labelText: 'Nota (opcional)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    final v = double.tryParse(amount.text.replaceAll(',', '.')) ?? 0;
    if (v <= 0 || FormV.money(amount.text, allowEmpty: false) != null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Monto inválido')));
      }
      return;
    }
    final m = await ref.read(membershipProvider.future);
    if (m == null) return;
    try {
      await ref.read(walletRepoProvider).addPayment(
            clinicId: m.clinicId,
            clientId: clientId,
            amount: v,
            note: note.text.trim().isEmpty ? null : note.text.trim(),
          );
      ref.invalidate(ledgerProvider(clientId));
      ref.invalidate(balancesProvider(true));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pago registrado.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger));
      }
    }
  }
}
