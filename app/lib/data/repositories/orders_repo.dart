import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/order.dart';
import '../models/prescription.dart';
import '../outbox.dart';
import '../providers/supabase_provider.dart';

class OrdersRepo {
  final SupabaseClient sb;
  final Outbox? outbox;
  OrdersRepo(this.sb, {this.outbox});

  /// Inserts a prescription first, then the order pointing to it
  /// (DB schema: `orders.prescription_id` → `prescriptions.id`).
  /// Wallet ledger rows are auto-created by DB trigger on order insert.
  Future<Order> createWithRx(Order order, Prescription rx) async {
    try {
      final rxRow =
          await sb.from('prescriptions').insert(rx.toInsert()).select().single();
      final rxId = (rxRow as Map)['id'] as String;
      final payload = order.toInsert()..['prescription_id'] = rxId;
      final orderRow =
          await sb.from('orders').insert(payload).select().single();
      return Order.fromMap(orderRow);
    } catch (e) {
      if (outbox != null) {
        await outbox!.enqueue('prescriptions', rx.toInsert());
        await outbox!.enqueue('orders', order.toInsert());
      }
      rethrow;
    }
  }

  Future<List<Order>> byClient(String clientId) async {
    final rows = await sb
        .from('orders')
        .select()
        .eq('client_id', clientId)
        .order('ordered_on', ascending: false);
    return (rows as List)
        .map((e) => Order.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<Order?> byId(String id) async {
    final rows = await sb.from('orders').select().eq('id', id).limit(1);
    if (rows.isEmpty) return null;
    return Order.fromMap(rows.first);
  }

  Future<String> nextFolio(String clinicId) async {
    try {
      final r = await sb.rpc('next_order_folio', params: {'p_clinic': clinicId});
      if (r != null && r.toString().isNotEmpty) return r.toString();
    } catch (_) {}
    final now = DateTime.now();
    final yy = now.year.toString().substring(2);
    final seq = now.millisecondsSinceEpoch.toString().substring(7);
    return 'SVL-$seq-$yy';
  }
}

final ordersRepoProvider = Provider<OrdersRepo>(
    (ref) => OrdersRepo(ref.watch(supabaseProvider), outbox: ref.watch(outboxProvider)));

final ordersByClientProvider = FutureProvider.family<List<Order>, String>(
  (ref, clientId) => ref.watch(ordersRepoProvider).byClient(clientId),
);

final orderByIdProvider = FutureProvider.family<Order?, String>(
  (ref, id) => ref.watch(ordersRepoProvider).byId(id),
);
