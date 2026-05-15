import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/models/prescription.dart';
import '../../data/repositories/clients_repo.dart';
import '../../data/repositories/orders_repo.dart';
import '../../data/repositories/prescriptions_repo.dart';

class ClientDetailScreen extends ConsumerWidget {
  final String clientId;
  const ClientDetailScreen({super.key, required this.clientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(clientByIdProvider(clientId));
    final orders = ref.watch(ordersByClientProvider(clientId));
    final rx = ref.watch(rxByClientProvider(clientId));
    return Scaffold(
      appBar: AppBar(
        title: client.maybeWhen(
          data: (c) => Text(c?.fullName ?? 'Cliente'),
          orElse: () => const Text('Cliente'),
        ),
        actions: [
          IconButton(
            tooltip: 'Cartera',
            onPressed: () => context.push('/wallet/$clientId'),
            icon: const Icon(Icons.account_balance_wallet_outlined),
          ),
        ],
      ),
      body: client.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (c) {
          if (c == null) return const Center(child: Text('No encontrado.'));
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _info(c),
              const SizedBox(height: 12),
              _sectionHeader('Historial Rx', Icons.visibility_outlined),
              rx.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (list) => list.isEmpty
                    ? const _Empty('Sin prescripciones registradas.')
                    : Column(children: list.map(_rxCard).toList()),
              ),
              const SizedBox(height: 12),
              _sectionHeader('Órdenes', Icons.receipt_long_outlined),
              orders.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (list) => list.isEmpty
                    ? const _Empty('Sin órdenes aún.')
                    : Column(
                        children: list
                            .map((o) => Card(
                                  child: ListTile(
                                    leading: const Icon(Icons.receipt_outlined),
                                    title: Text(o.folio,
                                        style: const TextStyle(
                                            fontFamily: 'DMMono',
                                            fontWeight: FontWeight.w800)),
                                    subtitle: Text(
                                        '${DateFormat('dd/MM/yyyy').format(o.orderDate)} · ${o.payForm} · \$${o.cost.toStringAsFixed(2)}'),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () =>
                                        context.push('/report/${o.id}'),
                                  ),
                                ))
                            .toList()),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _info(client) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(client.fullName,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Wrap(spacing: 12, runSpacing: 4, children: [
              if (client.age != null) _chip('${client.age} años'),
              if (client.phone != null) _chip(client.phone),
              if (client.diabetes) _chip('Diabetes', Colors.amber),
              if (client.hypertension) _chip('Hipertensión', Colors.amber),
            ]),
            if ([client.street, client.colonia, client.municipio]
                .any((s) => s != null && s.toString().isNotEmpty)) ...[
              const SizedBox(height: 8),
              Text(
                [client.street, client.colonia, client.municipio]
                    .whereType<String>()
                    .where((s) => s.isNotEmpty)
                    .join(', '),
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
          ]),
        ),
      );

  Widget _chip(String? text, [Color color = AppColors.greenSoft]) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(20)),
        child: Text(text ?? '',
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.navy)),
      );

  Widget _sectionHeader(String title, IconData icon) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(children: [
          Icon(icon, size: 18, color: AppColors.greenPrimary),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: AppColors.navy)),
        ]),
      );

  Widget _rxCard(Prescription p) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(DateFormat('dd MMM yyyy').format(p.visitDate),
                style: const TextStyle(
                    fontFamily: 'DMMono', fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            _rxRow('OD', p.odEsf, p.odCil, p.odEje, p.odAdd, p.odDip, p.odAlt),
            _rxRow('OI', p.oiEsf, p.oiCil, p.oiEje, p.oiAdd, p.oiDip, p.oiAlt),
          ]),
        ),
      );

  Widget _rxRow(String eye, double? esf, double? cil, int? eje,
          double? add, double? dip, double? alt) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          SizedBox(
              width: 32,
              child: Text(eye,
                  style: const TextStyle(
                      fontFamily: 'DMMono', fontWeight: FontWeight.w800))),
          _cell('ESF', esf), _cell('CIL', cil), _cell('EJE', eje),
          _cell('ADD', add), _cell('DIP', dip), _cell('ALT', alt),
        ]),
      );

  Widget _cell(String label, dynamic v) => Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(fontSize: 9, color: AppColors.muted)),
          Text(v?.toString() ?? '–',
              style: const TextStyle(
                  fontFamily: 'DMMono', fontWeight: FontWeight.w700)),
        ]),
      );
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text, style: const TextStyle(color: AppColors.muted)),
      );
}
