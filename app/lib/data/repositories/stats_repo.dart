import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/supabase_provider.dart';

class StatsSummary {
  final int ordersMonth;
  final double grossMonth;
  final double collectedMonth;
  final double activeDebt;
  const StatsSummary({
    required this.ordersMonth,
    required this.grossMonth,
    required this.collectedMonth,
    required this.activeDebt,
  });
}

class StatsRepo {
  final SupabaseClient sb;
  StatsRepo(this.sb);

  Future<StatsSummary> currentMonth(String clinicId) async {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);

    final orders = await sb
        .from('orders')
        .select('cost')
        .eq('clinic_id', clinicId)
        .gte('ordered_on', monthStart.toIso8601String().substring(0, 10));

    int count = 0;
    double gross = 0;
    for (final r in orders as List) {
      count++;
      gross += ((r as Map)['cost'] as num?)?.toDouble() ?? 0;
    }

    final pays = await sb
        .from('wallet_ledger')
        .select('amount, kind')
        .eq('clinic_id', clinicId)
        .gte('occurred_at', monthStart.toUtc().toIso8601String());

    double collected = 0;
    for (final r in pays as List) {
      final m = r as Map;
      if (m['kind'] == 'PAYMENT') {
        collected += (m['amount'] as num?)?.toDouble() ?? 0;
      }
    }

    final debts = await sb
        .from('client_balances')
        .select('balance')
        .eq('clinic_id', clinicId)
        .gt('balance', 0);
    double active = 0;
    for (final r in debts as List) {
      active += ((r as Map)['balance'] as num?)?.toDouble() ?? 0;
    }

    return StatsSummary(
      ordersMonth: count,
      grossMonth: gross,
      collectedMonth: collected,
      activeDebt: active,
    );
  }
}

final statsRepoProvider =
    Provider<StatsRepo>((ref) => StatsRepo(ref.watch(supabaseProvider)));

final statsSummaryProvider = FutureProvider<StatsSummary>((ref) async {
  final m = await ref.watch(membershipProvider.future);
  if (m == null) {
    return const StatsSummary(
        ordersMonth: 0, grossMonth: 0, collectedMonth: 0, activeDebt: 0);
  }
  return ref.watch(statsRepoProvider).currentMonth(m.clinicId);
});
