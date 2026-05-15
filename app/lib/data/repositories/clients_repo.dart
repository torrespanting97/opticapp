import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/client.dart';
import '../providers/supabase_provider.dart';

class ClientsRepo {
  final SupabaseClient sb;
  ClientsRepo(this.sb);

  Future<List<Client>> search(String clinicId, String q, {int limit = 50}) async {
    var query = sb.from('clients').select().eq('clinic_id', clinicId);
    if (q.trim().isNotEmpty) {
      query = query.ilike('name', '%${q.trim()}%');
    }
    final rows = await query.order('name').limit(limit);
    return (rows as List)
        .map((e) => Client.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  Future<Client?> byId(String id) async {
    final rows = await sb.from('clients').select().eq('id', id).limit(1);
    if (rows.isEmpty) return null;
    return Client.fromMap(rows.first);
  }

  Future<Client> upsert(Client c) async {
    final payload = c.toInsert();
    if (c.id.isNotEmpty) payload['id'] = c.id;
    final row = await sb.from('clients').upsert(payload).select().single();
    return _tryGeocode(Client.fromMap(row));
  }

  Future<Client> insert(Client c) async {
    final row = await sb.from('clients').insert(c.toInsert()).select().single();
    return _tryGeocode(Client.fromMap(row));
  }

  /// Geocode all clients in [clinicId] that have address data but no coordinates.
  /// Returns the number successfully geocoded.
  Future<int> geocodeMissing(String clinicId) async {
    final rows = await sb
        .from('clients')
        .select()
        .eq('clinic_id', clinicId)
        .filter('lat', 'is', null)
        .order('name');
    int count = 0;
    for (final row in rows as List) {
      final c = Client.fromMap(row as Map<String, dynamic>);
      final q = _buildQuery(c);
      if (q == null) continue;
      final coords = await _callGeocode(q);
      if (coords != null) {
        await _applyCoords(c.id, coords.$1, coords.$2);
        count++;
        await Future.delayed(const Duration(seconds: 2));
      }
    }
    return count;
  }

  // ── private helpers ──────────────────────────────────────────────────────

  Future<Client> _tryGeocode(Client c) async {
    final q = _buildQuery(c);
    if (q == null) return c;
    try {
      final coords = await _callGeocode(q);
      if (coords == null) return c;
      return _applyCoords(c.id, coords.$1, coords.$2);
    } catch (_) {
      return c;
    }
  }

  String? _buildQuery(Client c) {
    final parts = [c.street, c.colonia, c.municipio]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return null;
    final q = parts.join(', ');
    return (q.length >= 4 && q.length <= 200) ? q : null;
  }

  Future<(double, double)?> _callGeocode(String query) async {
    final res = await sb.functions.invoke('geocode', body: {'query': query});
    final data = res.data as Map<String, dynamic>?;
    if (data == null || data['ok'] != true) return null;
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return (lat, lng);
  }

  Future<Client> _applyCoords(String id, double lat, double lng) async {
    await sb.from('clients').update({
      'lat': lat,
      'lng': lng,
      'geocoded_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
    return (await byId(id))!;
  }
}

final clientsRepoProvider =
    Provider<ClientsRepo>((ref) => ClientsRepo(ref.watch(supabaseProvider)));

final clientsSearchProvider =
    FutureProvider.family<List<Client>, String>((ref, q) async {
  final m = await ref.watch(membershipProvider.future);
  if (m == null) return [];
  return ref.watch(clientsRepoProvider).search(m.clinicId, q);
});

final clientByIdProvider = FutureProvider.family<Client?, String>(
  (ref, id) => ref.watch(clientsRepoProvider).byId(id),
);
