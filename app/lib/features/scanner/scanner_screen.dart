import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme.dart';
import '../../data/providers/supabase_provider.dart';
import 'receipt_scanner_service.dart';

/// Pendant of the "Escáner IA" tab in the HTML template.
class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});
  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen> {
  Uint8List? _bytes;
  bool _busy = false;
  String? _err;
  String _provider = 'groq';

  Future<void> _pick(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src, imageQuality: 92, maxWidth: 2000);
    if (x == null) return;
    final raw = await x.readAsBytes();
    final bytes = await _compress(raw);
    setState(() { _bytes = bytes; _err = null; });
  }

  Future<Uint8List> _compress(Uint8List raw) async {
    try {
      return await FlutterImageCompress.compressWithList(
        raw, quality: 92, format: CompressFormat.jpeg, minWidth: 1600,
      );
    } on UnimplementedError {
      return raw;
    }
  }

  Future<void> _analyze() async {
    if (_bytes == null) return;
    setState(() { _busy = true; _err = null; });
    try {
      final svc = ReceiptScannerService(Supabase.instance.client);
      final d = await svc.extract(jpegBytes: _bytes!, provider: _provider);
      ref.read(extractedReceiptProvider.notifier).state = Map<String, dynamic>.from(d);
      if (mounted) context.go('/');
    } catch (e) {
      setState(() => _err = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'groq',   label: Text('⚡ Groq')),
                    ButtonSegment(value: 'gemini', label: Text('✨ Gemini')),
                  ],
                  selected: {_provider},
                  onSelectionChanged: (s) => setState(() => _provider = s.first),
                )),
              ]),
              const SizedBox(height: 16),
              if (_bytes != null)
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(_bytes!, height: 240, fit: BoxFit.cover, width: double.infinity),
                )
              else
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.greenAccent, width: 2, style: BorderStyle.solid),
                    borderRadius: BorderRadius.circular(14),
                    color: AppColors.greenMist,
                  ),
                  child: const Center(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.description_outlined, size: 40, color: AppColors.greenPrimary),
                      SizedBox(height: 8),
                      Text('Fotografía la Orden de Pedido',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      Text('JPG, PNG, WEBP, HEIC',
                          style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ]),
                  ),
                ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ElevatedButton.icon(
                  onPressed: () => _pick(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Cámara'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Galería'),
                ),
                if (_bytes != null)
                  ElevatedButton.icon(
                    onPressed: _busy ? null : _analyze,
                    icon: _busy
                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.auto_awesome),
                    label: Text(_busy ? 'Analizando…' : 'Analizar con IA'),
                  ),
              ]),
              if (_err != null) Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_err!, style: const TextStyle(color: AppColors.danger)),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}
