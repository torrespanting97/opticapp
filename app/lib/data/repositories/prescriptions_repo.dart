import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/prescription.dart';
import '../providers/supabase_provider.dart';

class PrescriptionsRepo {
  final SupabaseClient sb;
  PrescriptionsRepo(this.sb);

  Future<List<Prescription>> byClient(String clientId) async {
    final rows = await sb
        .from('prescriptions')
        .select()
        .eq('client_id', clientId)
        .order('taken_at', ascending: false);
    return (rows as List)
        .map((e) => Prescription.fromMap(e as Map<String, dynamic>))
        .toList();
  }
}

final prescriptionsRepoProvider = Provider<PrescriptionsRepo>(
    (ref) => PrescriptionsRepo(ref.watch(supabaseProvider)));

final rxByClientProvider = FutureProvider.family<List<Prescription>, String>(
  (ref, clientId) => ref.watch(prescriptionsRepoProvider).byClient(clientId),
);
