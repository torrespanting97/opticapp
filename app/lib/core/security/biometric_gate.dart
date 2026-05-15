// Biometric / device-PIN gate on app foreground.
// Used to wrap navigation away from the login screen so a stolen unlocked
// device still cannot read PHI without a biometric re-prompt.

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

class BiometricGate {
  BiometricGate._();
  static final BiometricGate I = BiometricGate._();

  final _auth = LocalAuthentication();
  bool _unlocked = false;
  DateTime _lastOk = DateTime.fromMillisecondsSinceEpoch(0);

  static const _gracePeriod = Duration(minutes: 5);

  Future<bool> ensure(BuildContext context, {String reason = 'Confirma tu identidad'}) async {
    if (_unlocked && DateTime.now().difference(_lastOk) < _gracePeriod) return true;
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck  = await _auth.canCheckBiometrics;
      if (!supported && !canCheck) {
        _unlocked = true; // fall through on devices without biometrics
        _lastOk = DateTime.now();
        return true;
      }
      final ok = await _auth.authenticate(
        localizedReason: reason,
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: false,
          useErrorDialogs: true,
        ),
      );
      _unlocked = ok;
      if (ok) _lastOk = DateTime.now();
      return ok;
    } catch (_) {
      return false;
    }
  }

  void invalidate() {
    _unlocked = false;
    _lastOk = DateTime.fromMillisecondsSinceEpoch(0);
  }
}
