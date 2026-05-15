import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../core/env.dart';
import '../../core/theme.dart';
import '../../data/providers/supabase_provider.dart';

/// Coverage map — clients geocoded by the `geocode` edge function.
/// Marker color reflects wallet balance.
class CoverageMapScreen extends ConsumerWidget {
  const CoverageMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(_mapPointsProvider);
    return Stack(children: [
      dataAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (points) {
          final center = points.isEmpty
              ? const LatLng(25.6866, -100.3161)
              : LatLng(
                  points.map((p) => p.lat).reduce((a, b) => a + b) / points.length,
                  points.map((p) => p.lng).reduce((a, b) => a + b) / points.length,
                );
          return FlutterMap(
            options: MapOptions(initialCenter: center, initialZoom: 11),
            children: [
              TileLayer(
                urlTemplate: Env.tileUrl,
                userAgentPackageName: 'mx.saludvisual.app',
              ),
              CircleLayer(
                circles: [
                  for (final p in points)
                    CircleMarker(
                      point: LatLng(p.lat, p.lng),
                      radius: 12 + (p.balance.clamp(0, 5000) / 200),
                      useRadiusInMeter: false,
                      color: (p.balance > 0
                              ? AppColors.danger
                              : AppColors.greenPrimary)
                          .withOpacity(0.25),
                      borderColor: p.balance > 0
                          ? AppColors.danger
                          : AppColors.greenPrimary,
                      borderStrokeWidth: 1.5,
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  for (final p in points)
                    Marker(
                      point: LatLng(p.lat, p.lng),
                      width: 20,
                      height: 20,
                      child: Tooltip(
                        message: '${p.name}\nSaldo: \$${p.balance.toStringAsFixed(2)}',
                        child: Icon(Icons.location_on,
                            size: 20,
                            color: p.balance > 0
                                ? AppColors.danger
                                : AppColors.greenPrimary),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
      Positioned(
        left: 12, top: 12,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: dataAsync.maybeWhen(
              data: (p) => Text('${p.length} clientes geocodificados',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12)),
              orElse: () => const Text('…'),
            ),
          ),
        ),
      ),
    ]);
  }
}

class _MapPoint {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final double balance;
  _MapPoint(this.id, this.name, this.lat, this.lng, this.balance);
}

final _mapPointsProvider = FutureProvider<List<_MapPoint>>((ref) async {
  final m = await ref.watch(membershipProvider.future);
  if (m == null) return [];
  final sb = ref.watch(supabaseProvider);
  final clients = await sb
      .from('clients')
      .select('id, name, lat, lng')
      .eq('clinic_id', m.clinicId)
      .not('lat', 'is', null)
      .not('lng', 'is', null);
  final balances = await sb
      .from('client_balances')
      .select('client_id, balance')
      .eq('clinic_id', m.clinicId);
  final balanceMap = <String, double>{};
  for (final r in (balances as List)) {
    balanceMap[(r as Map)['client_id'] as String] =
        ((r['balance'] as num?)?.toDouble()) ?? 0;
  }
  return (clients as List)
      .map((r) {
        final m = r as Map<String, dynamic>;
        return _MapPoint(
          m['id'] as String,
          (m['name'] ?? '') as String,
          (m['lat'] as num).toDouble(),
          (m['lng'] as num).toDouble(),
          balanceMap[m['id']] ?? 0,
        );
      })
      .toList();
});
