import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/repositories/stats_repo.dart';

final _money = NumberFormat.currency(locale: 'es_MX', symbol: '\$');

class StatsScreen extends ConsumerWidget {
  const StatsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(statsSummaryProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Reportes & Estadísticas',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(DateFormat('MMMM y', 'es').format(DateTime.now()),
            style: const TextStyle(color: AppColors.muted)),
        const SizedBox(height: 14),
        s.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e'),
          data: (data) => LayoutBuilder(builder: (ctx, c) {
            final cols = c.maxWidth < 600 ? 2 : 4;
            final cards = <(String, String, IconData, Color)>[
              ('Órdenes mes', data.ordersMonth.toString(),
                  Icons.receipt_long, AppColors.greenPrimary),
              ('Ingreso bruto', _money.format(data.grossMonth),
                  Icons.trending_up, AppColors.navy),
              ('Cobrado mes', _money.format(data.collectedMonth),
                  Icons.payments_outlined, AppColors.greenAccent),
              ('Deuda activa', _money.format(data.activeDebt),
                  Icons.warning_amber, AppColors.danger),
            ];
            return GridView.count(
              crossAxisCount: cols,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 2.2,
              children: cards
                  .map((e) => Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Icon(e.$3, color: e.$4, size: 16),
                                  const SizedBox(width: 6),
                                  Text(e.$1,
                                      style: const TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700)),
                                ]),
                                const Spacer(),
                                Text(e.$2,
                                    style: const TextStyle(
                                        fontFamily: 'DMMono',
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800)),
                              ]),
                        ),
                      ))
                  .toList(),
            );
          }),
        ),
        const SizedBox(height: 16),
        const Card(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Row(children: [
              Icon(Icons.insights, color: AppColors.greenPrimary),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Las vistas materializadas se refrescan cada noche por el cron stats-daily-refresh. '
                  'Gráficos por promotor / lab / municipio en próxima versión.',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
