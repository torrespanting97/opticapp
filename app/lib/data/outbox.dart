import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'providers/supabase_provider.dart';

/// A tiny offline outbox.
/// Writes that fail (no internet / 5xx) are enqueued under a secure-storage key
/// and flushed when connectivity returns.
///
/// Payload format:
/// { id, table, op:'insert', row:{...} }
class OutboxItem {
  final String id;
  final String table;
  final String op;
  final Map<String, dynamic> row;
  final DateTime queuedAt;
  OutboxItem({
    required this.id,
    required this.table,
    required this.op,
    required this.row,
    required this.queuedAt,
  });
  Map<String, dynamic> toJson() => {
        'id': id,
        'table': table,
        'op': op,
        'row': row,
        'queued_at': queuedAt.toIso8601String(),
      };
  factory OutboxItem.fromJson(Map<String, dynamic> j) => OutboxItem(
        id: j['id'] as String,
        table: j['table'] as String,
        op: j['op'] as String,
        row: Map<String, dynamic>.from(j['row'] as Map),
        queuedAt: DateTime.parse(j['queued_at'] as String),
      );
}

class Outbox {
  Outbox(this._sb);
  final SupabaseClient _sb;
  static const _key = 'sv_outbox_v1';
  static const _store = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static const _uuid = Uuid();

  final _items = <OutboxItem>[];
  bool _loaded = false;
  StreamSubscription? _connSub;
  final ValueNotifier<int> pendingCount = ValueNotifier(0);

  Future<void> _load() async {
    if (_loaded) return;
    final raw = await _store.read(key: _key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        _items.addAll(list.map((e) => OutboxItem.fromJson(e as Map<String, dynamic>)));
      } catch (_) {/* corrupt — start fresh */}
    }
    _loaded = true;
    pendingCount.value = _items.length;
  }

  Future<void> _persist() async {
    await _store.write(
      key: _key,
      value: jsonEncode(_items.map((e) => e.toJson()).toList()),
    );
    pendingCount.value = _items.length;
  }

  Future<void> enqueue(String table, Map<String, dynamic> row) async {
    await _load();
    _items.add(OutboxItem(
      id: _uuid.v4(),
      table: table,
      op: 'insert',
      row: row,
      queuedAt: DateTime.now(),
    ));
    await _persist();
  }

  Future<int> flush() async {
    await _load();
    if (_items.isEmpty) return 0;
    final done = <String>[];
    for (final it in List.of(_items)) {
      try {
        await _sb.from(it.table).insert(it.row);
        done.add(it.id);
      } catch (e) {
        if (kDebugMode) debugPrint('outbox flush fail ${it.table}: $e');
        break; // stop on first failure; keep order
      }
    }
    _items.removeWhere((e) => done.contains(e.id));
    await _persist();
    return done.length;
  }

  void start() {
    _connSub ??= Connectivity().onConnectivityChanged.listen((status) {
      final hasNet = status.any((s) => s != ConnectivityResult.none);
      if (hasNet) flush();
    });
  }

  void stop() {
    _connSub?.cancel();
    _connSub = null;
  }
}

final outboxProvider = Provider<Outbox>((ref) {
  final ob = Outbox(ref.watch(supabaseProvider));
  ob.start();
  ref.onDispose(ob.stop);
  return ob;
});
