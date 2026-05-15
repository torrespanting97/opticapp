import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/supabase_provider.dart';

class ClinicRepo {
  final SupabaseClient sb;
  ClinicRepo(this.sb);

  /// Creates a new clinic and an OWNER membership for the current user.
  /// Returns the new clinic_id.
  Future<String> createClinicForCurrentUser({
    required String name,
    String? phone,
    String? address,
  }) async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) {
      throw StateError('Sesión no iniciada.');
    }
    // RPC enforces single-owner clinic creation + audit.
    try {
      final id = await sb.rpc('create_clinic', params: {
        'p_name': name,
        if (phone != null) 'p_phone': phone,
        if (address != null) 'p_address': address,
      });
      if (id != null) return id.toString();
    } catch (_) {
      // Fallback to plain inserts (RLS must still allow these via membership trigger).
    }
    final clinic = await sb
        .from('clinics')
        .insert({
          'name': name,
          if (phone != null) 'phone': phone,
          if (address != null) 'address': address,
        })
        .select()
        .single();
    final clinicId = clinic['id'] as String;
    await sb.from('memberships').insert({
      'clinic_id': clinicId,
      'user_id': uid,
      'role': 'owner',
    });
    return clinicId;
  }
}

final clinicRepoProvider =
    Provider<ClinicRepo>((ref) => ClinicRepo(ref.watch(supabaseProvider)));
