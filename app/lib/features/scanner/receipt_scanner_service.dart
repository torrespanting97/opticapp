import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Calls the `extract-receipt` edge function with a base64-encoded image and
/// returns the structured JSON ready to fill the Nueva-Orden form.
class ReceiptScannerService {
  final SupabaseClient _sb;
  ReceiptScannerService(this._sb);

  /// [provider] = 'groq' | 'gemini' (server auto-falls back on failure).
  Future<Map<String, dynamic>> extract({
    required Uint8List jpegBytes,
    String provider = 'groq',
    String? model,
  }) async {
    final res = await _sb.functions.invoke('extract-receipt', body: {
      'image_base64': base64Encode(jpegBytes),
      'mime': 'image/jpeg',
      'provider': provider,
      if (model != null) 'model': model,
    });
    if (res.status >= 400) {
      throw Exception('extract-receipt failed: ${res.status} ${res.data}');
    }
    final body = res.data is String ? jsonDecode(res.data) : res.data;
    if (body is! Map || body['ok'] != true) {
      throw Exception('extract-receipt error: ${body is Map ? body['error'] : body}');
    }
    return Map<String, dynamic>.from(body['data']);
  }
}
