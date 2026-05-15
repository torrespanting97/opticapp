import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../data/repositories/appointments_repo.dart';

class CalendarSettingsScreen extends ConsumerStatefulWidget {
  const CalendarSettingsScreen({super.key});
  @override
  ConsumerState<CalendarSettingsScreen> createState() => _CalendarSettingsScreenState();
}

class _CalendarSettingsScreenState extends ConsumerState<CalendarSettingsScreen> {
  bool _loading = false;

  Future<void> _connect(String provider) async {
    setState(() => _loading = true);
    try {
      final url = await ref.read(appointmentsRepoProvider).startOAuth(provider);
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw Exception('No se pudo abrir el navegador');
      }
      // Deep link will return to salud-visual://oauth-success — handled in main.dart
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desconectar calendario'),
        content: const Text(
            'Se dejará de sincronizar con tu calendario externo. Las citas ya importadas quedan en la app.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _loading = true);
    try {
      await ref.read(appointmentsRepoProvider).disconnectCalendar();
      ref.invalidate(calendarProfileProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Calendario desconectado.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(calendarProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Calendario externo')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (data) {
          final provider = data['calendar_provider'] as String? ?? 'none';
          final linked   = provider != 'none' && data['calendar_refresh'] != null;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Status card ───────────────────────────────────────
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    CircleAvatar(
                      backgroundColor: linked ? AppColors.greenSoft : Colors.grey.shade100,
                      child: Icon(
                        linked ? Icons.check_circle : Icons.link_off,
                        color: linked ? AppColors.greenPrimary : AppColors.muted,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          linked
                              ? '${provider == 'google' ? 'Google Calendar' : 'Outlook'} vinculado'
                              : 'Sin calendario vinculado',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          linked
                              ? 'Las citas se sincronizan automáticamente cada 10 min.'
                              : 'Conecta tu cuenta para sincronizar citas.',
                          style: const TextStyle(fontSize: 12, color: AppColors.muted),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),

              const SizedBox(height: 16),
              const Text('Conectar con', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),

              // ── Google ────────────────────────────────────────────
              _ProviderTile(
                icon: Icons.calendar_month,
                color: Colors.blue,
                label: 'Google Calendar',
                description: 'Gmail, Google Workspace',
                linked: linked && provider == 'google',
                loading: _loading,
                onConnect: () => _connect('google'),
                onDisconnect: _disconnect,
              ),

              const SizedBox(height: 8),

              // ── Outlook ───────────────────────────────────────────
              _ProviderTile(
                icon: Icons.event_note,
                color: Colors.indigo,
                label: 'Outlook / Microsoft',
                description: 'Hotmail, Outlook, Office 365',
                linked: linked && provider == 'outlook',
                loading: _loading,
                onConnect: () => _connect('outlook'),
                onDisconnect: _disconnect,
                disabled: true, // Enable once MS credentials are configured
                disabledReason: 'Próximamente — configura MS_CLIENT_ID en .env',
              ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),

              // ── Info ──────────────────────────────────────────────
              const _InfoRow(
                icon: Icons.sync,
                text: 'Sincronización automática cada 10 minutos',
              ),
              const _InfoRow(
                icon: Icons.notifications_active,
                text: 'Recordatorios automáticos 24 h y 1 h antes al cliente',
              ),
              const _InfoRow(
                icon: Icons.message,
                text: 'Notificaciones WhatsApp al cliente al confirmar o cancelar',
              ),
              const _InfoRow(
                icon: Icons.mail_outline,
                text: 'Correo electrónico al cliente al confirmar o cancelar',
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProviderTile extends StatelessWidget {
  const _ProviderTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.description,
    required this.linked,
    required this.loading,
    required this.onConnect,
    required this.onDisconnect,
    this.disabled = false,
    this.disabledReason,
  });

  final IconData icon;
  final Color color;
  final String label;
  final String description;
  final bool linked;
  final bool loading;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;
  final bool disabled;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(disabled && disabledReason != null ? disabledReason! : description,
            style: const TextStyle(fontSize: 12)),
        trailing: loading
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : disabled
                ? const Icon(Icons.lock_outline, color: AppColors.muted)
                : linked
                    ? OutlinedButton(
                        style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.danger)),
                        onPressed: onDisconnect,
                        child: const Text('Desconectar',
                            style: TextStyle(color: AppColors.danger)),
                      )
                    : FilledButton(
                        onPressed: onConnect,
                        child: const Text('Conectar'),
                      ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon, size: 18, color: AppColors.muted),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.muted))),
      ]),
    );
  }
}
