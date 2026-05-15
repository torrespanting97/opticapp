import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Single Supabase client across the app.
final supabaseProvider = Provider<SupabaseClient>((_) => Supabase.instance.client);

/// Reactive auth state — anything that watches this rebuilds on sign-in/out.
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseProvider).auth.onAuthStateChange,
);

/// Current user's active clinic membership (clinic_id, role).
/// Read once after login; cached for the session.
class Membership {
  final String clinicId;
  final String role; // OWNER | OPTO | PROMOTER
  final String clinicName;
  const Membership(
      {required this.clinicId, required this.role, required this.clinicName});
}

/// All labs the current user belongs to.
final allLabsProvider = FutureProvider<List<Membership>>((ref) async {
  final sb = ref.watch(supabaseProvider);
  ref.watch(authStateProvider);
  final uid = sb.auth.currentUser?.id;
  if (uid == null) return [];
  final rows = await sb
      .from('memberships')
      .select('clinic_id, role, clinics(name)')
      .eq('user_id', uid);
  return rows
      .map<Membership>((r) => Membership(
            clinicId: r['clinic_id'] as String,
            role: (r['role'] as String?) ?? 'owner',
            clinicName: (r['clinics']?['name'] as String?) ?? 'Lab',
          ))
      .toList();
});

/// Explicitly selected lab for the session — persists across orders.
final selectedLabProvider = StateProvider<Membership?>((_) => null);

/// Active lab: explicit selection wins; otherwise first available from DB.
final membershipProvider = FutureProvider<Membership?>((ref) async {
  final selected = ref.watch(selectedLabProvider);
  if (selected != null) return selected;
  final labs = await ref.watch(allLabsProvider.future);
  return labs.isEmpty ? null : labs.first;
});

/// Receipt extraction result bridge: scanner writes here, NewOrder reads it.
final extractedReceiptProvider =
    StateProvider<Map<String, dynamic>?>((_) => null);
