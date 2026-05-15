// Lightweight i18n. Drop-in replacement until full flutter_localizations setup.
// All UI strings reference T.of(context).key — defaults Spanish.

import 'package:flutter/widgets.dart';

class T {
  final Locale locale;
  T(this.locale);

  static T of(BuildContext context) =>
      T(Localizations.localeOf(context));

  bool get _en => locale.languageCode == 'en';

  String get appName => 'Salud Visual';
  String get login => _en ? 'Sign in' : 'Iniciar sesión';
  String get signup => _en ? 'Create account' : 'Crear cuenta';
  String get clients => _en ? 'Clients' : 'Clientes';
  String get newOrder => _en ? 'New order' : 'Nueva orden';
  String get scanner => _en ? 'AI scanner' : 'Escáner IA';
  String get appointments => _en ? 'Appointments' : 'Citas';
  String get wallet => _en ? 'Wallet' : 'Cartera';
  String get map => _en ? 'Coverage map' : 'Mapa de cobertura';
  String get reports => _en ? 'Reports' : 'Reportes';
  String get save => _en ? 'Save' : 'Guardar';
  String get cancel => _en ? 'Cancel' : 'Cancelar';
}
