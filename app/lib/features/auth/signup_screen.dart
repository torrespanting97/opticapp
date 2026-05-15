import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/security/form_v.dart';
import '../../data/providers/supabase_provider.dart';
import '../../data/repositories/clinic_repo.dart';

/// Self-service clinic onboarding. Creates the auth user, then a clinic + OWNER membership.
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});
  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _clinic = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _fullName.dispose();
    _clinic.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      final sb = ref.read(supabaseProvider);
      final res = await sb.auth.signUp(
        email: _email.text.trim(),
        password: _password.text,
        data: {'full_name': _fullName.text.trim()},
      );
      if (res.user == null) {
        throw const AuthException('No se pudo crear la cuenta.');
      }
      // If email confirmation is on, signUp does not return a session.
      // Wait for the session (or surface message).
      if (sb.auth.currentSession == null) {
        try {
          await sb.auth.signInWithPassword(
              email: _email.text.trim(), password: _password.text);
        } catch (_) {/* email confirmation required */}
      }
      if (sb.auth.currentUser == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Revisa tu correo para confirmar la cuenta.')));
        Navigator.of(context).pop();
        return;
      }
      await ref.read(clinicRepoProvider).createClinicForCurrentUser(
            name: _clinic.text.trim(),
            phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
          );
      ref.invalidate(membershipProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Crear clínica')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Bienvenido a Salud Visual',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('Crea tu clínica en 30 segundos.',
                    style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 18),
                _f(controller: _fullName, label: 'Tu nombre completo',
                    validator: FormV.required('Nombre')),
                _f(controller: _clinic, label: 'Nombre de la clínica',
                    validator: FormV.required('Clínica')),
                _f(controller: _email, label: 'Correo', keyboard: TextInputType.emailAddress,
                    validator: FormV.email),
                _f(controller: _phone, label: 'Teléfono (opcional)',
                    keyboard: TextInputType.phone, validator: FormV.phoneOptional),
                _f(controller: _password, label: 'Contraseña', obscure: true,
                    validator: FormV.password),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Crear cuenta'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Ya tengo cuenta'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _f({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboard,
    bool obscure = false,
    String? Function(String?)? validator,
  }) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextFormField(
          controller: controller,
          keyboardType: keyboard,
          obscureText: obscure,
          decoration: InputDecoration(labelText: label),
          validator: validator,
        ),
      );
}
