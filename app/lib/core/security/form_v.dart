// Form-friendly wrappers around the throw-based V class.
// Returns null when valid, error message when invalid — what Flutter Form expects.

import 'validators.dart';

class FormV {
  static String? Function(String?) required(String field) =>
      (v) => (v == null || v.trim().isEmpty) ? '$field requerido' : null;

  static String? email(String? v) {
    if (v == null || v.isEmpty) return 'Correo requerido';
    try { V.email('email', v); return null; }
    catch (_) { return 'Correo no válido'; }
  }

  static String? password(String? v) {
    if (v == null || v.length < 8) return 'Mínimo 8 caracteres';
    return null;
  }

  static String? phoneOptional(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    try { V.phoneMx('phone', v); return null; }
    catch (_) { return 'Teléfono no válido'; }
  }

  static String? rx(String? v) {
    if (v == null || v.trim().isEmpty) return null;
    try { V.rxValue('rx', v); return null; }
    catch (_) { return 'Formato Rx'; }
  }

  static String? money(String? v, {bool allowEmpty = true}) {
    if (v == null || v.trim().isEmpty) return allowEmpty ? null : 'Requerido';
    try { V.money('money', v); return null; }
    catch (_) { return 'Importe inválido'; }
  }

  static String? integer(String? v, {int min = 0, int max = 200, bool allowEmpty = true}) {
    if (v == null || v.trim().isEmpty) return allowEmpty ? null : 'Requerido';
    final n = int.tryParse(v);
    if (n == null || n < min || n > max) return '$min–$max';
    return null;
  }
}
