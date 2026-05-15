import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../core/theme.dart';
import '../../data/models/appointment.dart';
import '../../data/providers/supabase_provider.dart';
import '../../data/repositories/appointments_repo.dart';

// ── Status config ─────────────────────────────────────────────────────────
const _statusLabel = {
  'scheduled':  'Agendada',
  'confirmed':  'Confirmada',
  'done':       'Completada',
  'cancelled':  'Cancelada',
  'no_show':    'No asistió',
};
const _statusColor = {
  'scheduled':  Color(0xFF1565C0), // blue
  'confirmed':  Color(0xFF2E7D32), // green
  'done':       Color(0xFF757575), // grey
  'cancelled':  Color(0xFFC62828), // red
  'no_show':    Color(0xFFE65100), // orange
};

Color _statusBg(String s) => (_statusColor[s] ?? Colors.grey).withValues(alpha: 0.12);

// ─────────────────────────────────────────────────────────────────────────
class AppointmentsScreen extends ConsumerStatefulWidget {
  const AppointmentsScreen({super.key});
  @override
  ConsumerState<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends ConsumerState<AppointmentsScreen> {
  DateTime _focused  = DateTime.now();
  DateTime _selected = DateTime.now();
  bool _syncing      = false;

  // ── Calendar month range ──────────────────────────────────────────
  ({DateTime from, DateTime to}) get _monthRange => (
        from: DateTime(_focused.year, _focused.month, 1),
        to:   DateTime(_focused.year, _focused.month + 1, 1),
      );

  void _invalidateMonth() =>
      ref.invalidate(appointmentsRangeProvider(_monthRange));

  // ── Sync ──────────────────────────────────────────────────────────
  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final r       = await ref.read(appointmentsRepoProvider).triggerSync();
      final pulled  = r['pulled'] ?? r['imported'] ?? r['count'] ?? 0;
      final pushed  = r['pushed'] ?? 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Sincronizado. ↓$pulled importadas · ↑$pushed exportadas'),
        ));
      }
      _invalidateMonth();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error al sincronizar: $e'),
          backgroundColor: AppColors.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  // ── Create appointment dialog ─────────────────────────────────────
  Future<void> _newAppointment() async {
    final titleCtrl = TextEditingController();
    final noteCtrl  = TextEditingController();
    DateTime start  = DateTime(
        _selected.year, _selected.month, _selected.day, 9);
    int durationMin = 30;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        return AlertDialog(
          title: const Text('Nueva cita'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Título *')),
              TextFormField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'Notas')),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Inicio'),
                    child: Text(DateFormat('dd/MM HH:mm').format(start)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_calendar),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: start,
                      firstDate: DateTime.now().subtract(const Duration(days: 1)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d == null) return;
                    if (!ctx.mounted) return;
                    final t = await showTimePicker(
                        context: ctx, initialTime: TimeOfDay.fromDateTime(start));
                    if (t == null) return;
                    set(() => start =
                        DateTime(d.year, d.month, d.day, t.hour, t.minute));
                  },
                ),
              ]),
              DropdownButtonFormField<int>(
                initialValue: durationMin,
                decoration: const InputDecoration(labelText: 'Duración'),
                items: [15, 30, 45, 60, 90]
                    .map((m) => DropdownMenuItem(value: m, child: Text('$m min')))
                    .toList(),
                onChanged: (v) => set(() => durationMin = v ?? 30),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar')),
          ],
        );
      }),
    );

    if (saved != true || titleCtrl.text.trim().isEmpty) return;
    final m = await ref.read(membershipProvider.future);
    if (m == null) return;
    await ref.read(appointmentsRepoProvider).insert(Appointment(
          clinicId: m.clinicId,
          startsAt: start,
          endsAt:   start.add(Duration(minutes: durationMin)),
          title:    titleCtrl.text.trim(),
          notes:    noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
        ));
    _invalidateMonth();
    ref.invalidate(pendingActionProvider);
  }

  // ── Edit appointment dialog ───────────────────────────────────────
  Future<void> _editAppointment(Appointment a) async {
    final titleCtrl = TextEditingController(text: a.title);
    final noteCtrl  = TextEditingController(text: a.notes ?? '');
    DateTime start  = a.startsAt.toLocal();
    int durationMin =
        a.endsAt.difference(a.startsAt).inMinutes.clamp(15, 120);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, set) {
        return AlertDialog(
          title: const Text('Editar cita'),
          content: SizedBox(
            width: 420,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Título *')),
              TextFormField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'Notas')),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Inicio'),
                    child: Text(DateFormat('dd/MM HH:mm').format(start)),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_calendar),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: start,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d == null) return;
                    if (!ctx.mounted) return;
                    final t = await showTimePicker(
                        context: ctx,
                        initialTime: TimeOfDay.fromDateTime(start));
                    if (t == null) return;
                    set(() => start =
                        DateTime(d.year, d.month, d.day, t.hour, t.minute));
                  },
                ),
              ]),
              DropdownButtonFormField<int>(
                initialValue: [15, 30, 45, 60, 90].contains(durationMin)
                    ? durationMin
                    : 30,
                decoration: const InputDecoration(labelText: 'Duración'),
                items: [15, 30, 45, 60, 90]
                    .map((m) => DropdownMenuItem(value: m, child: Text('$m min')))
                    .toList(),
                onChanged: (v) => set(() => durationMin = v ?? 30),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Guardar')),
          ],
        );
      }),
    );

    if (saved != true || titleCtrl.text.trim().isEmpty) return;
    final updated = a.copyWith(
      startsAt: start,
      endsAt:   start.add(Duration(minutes: durationMin)),
      title:    titleCtrl.text.trim(),
      notes:    noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
    );
    await ref.read(appointmentsRepoProvider).update(updated);
    _invalidateMonth();
    ref.invalidate(pendingActionProvider);
  }

  // ── Delete ────────────────────────────────────────────────────────
  Future<void> _deleteAppointment(Appointment a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar cita'),
        content: Text('¿Eliminar "${a.title}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || a.id == null) return;
    await ref.read(appointmentsRepoProvider).delete(a.id!);
    _invalidateMonth();
    ref.invalidate(pendingActionProvider);
  }

  // ── Change status ─────────────────────────────────────────────────
  Future<void> _changeStatus(Appointment a, String newStatus) async {
    if (a.id == null) return;

    // Confirm cancellation explicitly
    if (newStatus == 'cancelled') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cancelar cita'),
          content: const Text(
              'Se notificará al cliente vía WhatsApp y correo. ¿Continuar?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Atrás')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sí, cancelar'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    try {
      await ref.read(appointmentsRepoProvider).changeStatus(a.id!, newStatus);
      _invalidateMonth();
      ref.invalidate(pendingActionProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Cita marcada como ${_statusLabel[newStatus] ?? newStatus}.'),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.danger,
        ));
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final list = ref.watch(appointmentsRangeProvider(_monthRange));
    final pending = ref.watch(pendingActionProvider);

    final todayAppts = list.maybeWhen(
      data: (all) => all
          .where((a) =>
              a.startsAt.toLocal().year == _selected.year &&
              a.startsAt.toLocal().month == _selected.month &&
              a.startsAt.toLocal().day == _selected.day)
          .toList(),
      orElse: () => <Appointment>[],
    );

    final pendingList = pending.maybeWhen(
      data: (p) => p,
      orElse: () => <Appointment>[],
    );

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header row ──────────────────────────────────────────────
        Row(children: [
          const Text('Citas',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const Spacer(),
          IconButton(
            tooltip: 'Configurar calendario',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings/calendar'),
          ),
          const SizedBox(width: 4),
          OutlinedButton.icon(
            onPressed: _syncing ? null : _sync,
            icon: _syncing
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.sync),
            label: const Text('Sincronizar'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _newAppointment,
            icon: const Icon(Icons.add),
            label: const Text('Nueva'),
          ),
        ]),
        const SizedBox(height: 8),

        // ── Pending action banner ────────────────────────────────────
        if (pendingList.isNotEmpty)
          _PendingBanner(
            count: pendingList.length,
            appointments: pendingList,
            onAction: _changeStatus,
          ),

        // ── Calendar ─────────────────────────────────────────────────
        Card(
          child: TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2035, 12, 31),
            focusedDay: _focused,
            selectedDayPredicate: (d) => isSameDay(d, _selected),
            onDaySelected: (s, f) =>
                setState(() { _selected = s; _focused = f; }),
            onPageChanged: (f) => setState(() => _focused = f),
            eventLoader: (day) => list.maybeWhen(
              data: (all) => all
                  .where((a) =>
                      a.startsAt.toLocal().year == day.year &&
                      a.startsAt.toLocal().month == day.month &&
                      a.startsAt.toLocal().day == day.day)
                  .toList(),
              orElse: () => const [],
            ),
            calendarStyle: const CalendarStyle(
              todayDecoration: BoxDecoration(
                  color: AppColors.greenAccent, shape: BoxShape.circle),
              selectedDecoration: BoxDecoration(
                  color: AppColors.greenPrimary, shape: BoxShape.circle),
              markerDecoration: BoxDecoration(
                  color: AppColors.navy, shape: BoxShape.circle),
            ),
          ),
        ),
        const SizedBox(height: 8),

        // ── Appointment list for selected day ─────────────────────────
        Expanded(
          child: todayAppts.isEmpty
              ? const Center(
                  child: Text('Sin citas este día.',
                      style: TextStyle(color: AppColors.muted)))
              : ListView.builder(
                  itemCount: todayAppts.length,
                  itemBuilder: (_, i) => _AppointmentTile(
                    appointment: todayAppts[i],
                    onEdit: () => _editAppointment(todayAppts[i]),
                    onDelete: () => _deleteAppointment(todayAppts[i]),
                    onChangeStatus: (s) => _changeStatus(todayAppts[i], s),
                  ),
                ),
        ),
      ]),
    );
  }
}

// ── Pending action banner ─────────────────────────────────────────────────
class _PendingBanner extends StatefulWidget {
  const _PendingBanner({
    required this.count,
    required this.appointments,
    required this.onAction,
  });
  final int count;
  final List<Appointment> appointments;
  final Future<void> Function(Appointment, String) onAction;

  @override
  State<_PendingBanner> createState() => _PendingBannerState();
}

class _PendingBannerState extends State<_PendingBanner> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFFFFF8E1),
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(children: [
        ListTile(
          leading: const Icon(Icons.pending_actions, color: Color(0xFFF57F17)),
          title: Text(
            '${widget.count} cita${widget.count > 1 ? 's' : ''} pendiente${widget.count > 1 ? 's' : ''} de cerrar',
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: Color(0xFFF57F17)),
          ),
          subtitle: const Text(
              'Pasaron sin ser marcadas como completadas.',
              style: TextStyle(fontSize: 12)),
          trailing: IconButton(
            icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
            onPressed: () => setState(() => _expanded = !_expanded),
          ),
        ),
        if (_expanded)
          ...widget.appointments.map((a) => Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.title,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                          Text(
                            DateFormat('dd/MM · HH:mm')
                                .format(a.startsAt.toLocal()),
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.muted),
                          ),
                        ]),
                  ),
                  TextButton(
                    onPressed: () => widget.onAction(a, 'done'),
                    child: const Text('Completar'),
                  ),
                  TextButton(
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.danger),
                    onPressed: () => widget.onAction(a, 'no_show'),
                    child: const Text('No asistió'),
                  ),
                ]),
              )),
        if (_expanded) const SizedBox(height: 8),
      ]),
    );
  }
}

// ── Appointment tile ──────────────────────────────────────────────────────
class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile({
    required this.appointment,
    required this.onEdit,
    required this.onDelete,
    required this.onChangeStatus,
  });

  final Appointment appointment;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final void Function(String) onChangeStatus;

  @override
  Widget build(BuildContext context) {
    final a      = appointment;
    final status = a.status;
    final color  = _statusColor[status] ?? AppColors.muted;
    final bg     = _statusBg(status);
    final closed = status == 'done' || status == 'cancelled' || status == 'no_show';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Source icon
          CircleAvatar(
            backgroundColor: bg,
            child: Icon(
              a.source == 'GOOGLE'
                  ? Icons.calendar_month
                  : a.source == 'OUTLOOK'
                      ? Icons.event_note
                      : Icons.event,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),

          // Content
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title + status chip
                  Row(children: [
                    Expanded(
                      child: Text(a.title,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _statusLabel[status] ?? status,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: color),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  // Time
                  Text(
                    '${DateFormat('HH:mm').format(a.startsAt.toLocal())} – '
                    '${DateFormat('HH:mm').format(a.endsAt.toLocal())}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.muted),
                  ),
                  if (a.notes != null && a.notes!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(a.notes!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.muted)),
                  ],
                  if (a.source != 'INTERNAL') ...[
                    const SizedBox(height: 4),
                    Text(a.source,
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.muted)),
                  ],

                  // ── Action buttons ─────────────────────────────────
                  if (!closed) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, children: [
                      if (status == 'scheduled')
                        _ActionChip(
                          label: 'Confirmar',
                          color: const Color(0xFF2E7D32),
                          onTap: () => onChangeStatus('confirmed'),
                        ),
                      if (status == 'confirmed')
                        _ActionChip(
                          label: 'Completar',
                          color: AppColors.muted,
                          onTap: () => onChangeStatus('done'),
                        ),
                      _ActionChip(
                        label: 'Cancelar',
                        color: AppColors.danger,
                        onTap: () => onChangeStatus('cancelled'),
                      ),
                    ]),
                  ],
                ]),
          ),

          // Overflow menu
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, size: 18),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('Editar')),
              const PopupMenuItem(
                  value: 'delete',
                  child: Text('Eliminar',
                      style: TextStyle(color: AppColors.danger))),
            ],
            onSelected: (v) {
              if (v == 'edit') onEdit();
              if (v == 'delete') onDelete();
            },
          ),
        ]),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip(
      {required this.label, required this.color, required this.onTap});
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
