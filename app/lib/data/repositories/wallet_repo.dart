import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/wallet_entry.dart';
import '../providers/supabase_provider.dart';

class WalletRepo {
  final SupabaseClient sb;
  WalletRepo(this.sb);

  Future<List<WalletEntry>> ledger(String clientId) async {
    final rows = await sb
        .from('wallet_ledger')
        .select()
        .eq('client_id', clientId)
        .order('occurred_at', ascending: false);
    return (rows as List)
        .map((e) => WalletEntry.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Joins `client_balances` (client_id, clinic_id, balance) with `clients`
  /// to enrich rows with the client name expected by the UI.
  Future<List<ClientBalance>> balances(String clinicId,
      {bool onlyDebtors = false}) async {
    var q = sb
        .from('client_balances')
        .select('client_id, clinic_id, balance, clients!inner(name)')
        .eq('clinic_id', clinicId);
    if (onlyDebtors) q = q.gt('balance', 0);
    final rows = await q.order('balance', ascending: false).limit(500);
    return (rows as List).map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      final c = m['clients'];
      if (c is Map && c['name'] != null) m['name'] = c['name'];
      return ClientBalance.fromMap(m);
    }).toList();
  }

  Future<WalletEntry> addPayment({
    required String clinicId,
    required String clientId,
    String? orderId,
    required double amount,
    String? note,
  }) async {
    final row = await sb
        .from('wallet_ledger')
        .insert({
          'clinic_id': clinicId,
          'client_id': clientId,
          if (orderId != null) 'order_id': orderId,
          'occurred_at': DateTime.now().toUtc().toIso8601String(),
          'kind': 'PAYMENT',
          'amount': amount,
          if (note != null) 'note': note,
        })
        .select()
        .single();
    return WalletEntry.fromMap(row);
  }
}

final walletRepoProvider =
    Provider<WalletRepo>((ref) => WalletRepo(ref.watch(supabaseProvider)));

final balancesProvider =
    FutureProvider.family<List<ClientBalance>, bool>((ref, onlyDebtors) async {
  final m = await ref.watch(membershipProvider.future);
  if (m == null) return [];
  return ref.watch(walletRepoProvider).balances(m.clinicId, onlyDebtors: onlyDebtors);
});

final ledgerProvider = FutureProvider.family<List<WalletEntry>, String>(
  (ref, clientId) => ref.watch(walletRepoProvider).ledger(clientId),
);
