import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/appointment.dart';
import '../providers/supabase_provider.dart';

class AppointmentsRepo {
  final SupabaseClient sb;
  AppointmentsRepo(this.sb);

  // ── Queries ─────────────────────────────────────────────────────
  Future<List<Appointment>> range(
      String clinicId, DateTime from, DateTime to) async {
    final rows = await sb
        .from('appointments')
        .select()
        .eq('clinic_id', clinicId)
        .gte('starts_at', from.toUtc().toIso8601String())
        .lt('starts_at', to.toUtc().toIso8601String())
        .order('starts_at');
    return (rows as List)
        .map((e) => Appointment.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Returns appointments that are past but not yet closed (pending action).
  Future<List<Appointment>> pendingAction(String clinicId) async {
    final rows = await sb
        .from('appointments')
        .select()
        .eq('clinic_id', clinicId)
        .lt('ends_at', DateTime.now().toUtc().toIso8601String())
        .not('status', 'in', '("done","cancelled","no_show")')
        .order('starts_at', ascending: false)
        .limit(50);
    return (rows as List)
        .map((e) => Appointment.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  // ── Mutations ────────────────────────────────────────────────────
  Future<Appointment> insert(Appointment a) async {
    final row =
        await sb.from('appointments').insert(a.toInsert()).select().single();
    return Appointment.fromMap(row);
  }

  Future<Appointment> update(Appointment a) async {
    if (a.id == null) throw ArgumentError('Appointment.id is required for update');
    final row = await sb
        .from('appointments')
        .update({
          'starts_at': a.startsAt.toUtc().toIso8601String(),
          'ends_at':   a.endsAt.toUtc().toIso8601String(),
          'title':     a.title,
          'notes':     a.notes,
        })
        .eq('id', a.id!)
        .select()
        .single();
    return Appointment.fromMap(row);
  }

  Future<Appointment> updateStatus(String id, String status) async {
    final row = await sb
        .from('appointments')
        .update({'status': status})
        .eq('id', id)
        .select()
        .single();
    return Appointment.fromMap(row);
  }

  Future<void> delete(String id) =>
      sb.from('appointments').delete().eq('id', id);

  // ── Calendar sync ────────────────────────────────────────────────
  Future<Map<String, dynamic>> triggerSync() async {
    final r = await sb.functions.invoke('calendar-sync');
    return Map<String, dynamic>.from(r.data as Map? ?? {});
  }

  // ── Status change ─────────────────────────────────────────────────
  /// Updates status in DB. The pg_net trigger (0006_notify_service.sql)
  /// automatically fires the Python notify service for WhatsApp + email.
  Future<Appointment> changeStatus(String id, String newStatus) =>
      updateStatus(id, newStatus);

  // ── OAuth ────────────────────────────────────────────────────────
  /// Returns the Google (or Outlook) authorization URL. Open it with url_launcher.
  Future<String> startOAuth(String provider) async {
    final r = await sb.functions.invoke('oauth-start', body: {'provider': provider});
    final data = Map<String, dynamic>.from(r.data as Map? ?? {});
    final url = data['url'] as String?;
    if (url == null) throw Exception('oauth-start returned no URL');
    return url;
  }

  Future<void> disconnectCalendar() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return;
    await sb.from('profiles').update({
      'calendar_provider': 'none',
      'calendar_refresh':  null,
    }).eq('id', uid);
  }

  Future<Map<String, dynamic>> calendarProfile() async {
    final uid = sb.auth.currentUser?.id;
    if (uid == null) return {};
    final row = await sb
        .from('profiles')
        .select('calendar_provider, calendar_refresh')
        .eq('id', uid)
        .single();
    return Map<String, dynamic>.from(row as Map);
  }
}

final appointmentsRepoProvider = Provider<AppointmentsRepo>(
    (ref) => AppointmentsRepo(ref.watch(supabaseProvider)));

final appointmentsRangeProvider = FutureProvider.family<List<Appointment>,
    ({DateTime from, DateTime to})>((ref, range) async {
  final m = await ref.watch(membershipProvider.future);
  if (m == null) return [];
  return ref.watch(appointmentsRepoProvider).range(m.clinicId, range.from, range.to);
});

final pendingActionProvider = FutureProvider<List<Appointment>>((ref) async {
  final m = await ref.watch(membershipProvider.future);
  if (m == null) return [];
  return ref.watch(appointmentsRepoProvider).pendingAction(m.clinicId);
});

final calendarProfileProvider = FutureProvider<Map<String, dynamic>>((ref) =>
    ref.watch(appointmentsRepoProvider).calendarProfile());
