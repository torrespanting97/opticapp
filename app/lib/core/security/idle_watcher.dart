// Idle-watcher — auto-logout after inactivity.
//   Mobile  : 15 minutes
//   Desktop : 30 minutes
// Wrap MaterialApp with `IdleWatcher(child: ...)`.
// Pointer + keyboard events reset the timer.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'biometric_gate.dart';

class IdleWatcher extends StatefulWidget {
  const IdleWatcher({super.key, required this.child});
  final Widget child;

  @override
  State<IdleWatcher> createState() => _IdleWatcherState();
}

class _IdleWatcherState extends State<IdleWatcher> with WidgetsBindingObserver {
  Timer? _t;

  Duration get _timeout {
    if (kIsWeb) return const Duration(minutes: 15);
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return const Duration(minutes: 30);
      default:
        return const Duration(minutes: 15);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reset();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _t?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      BiometricGate.I.invalidate(); // force re-prompt
    }
  }

  void _reset() {
    _t?.cancel();
    _t = Timer(_timeout, _logout);
  }

  Future<void> _logout() async {
    try { await Supabase.instance.client.auth.signOut(); } catch (_) {}
    BiometricGate.I.invalidate();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown:  (_) => _reset(),
      onPointerMove:  (_) => _reset(),
      onPointerHover: (PointerHoverEvent _) => _reset(),
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, __) { _reset(); return KeyEventResult.ignored; },
        child: widget.child,
      ),
    );
  }
}
