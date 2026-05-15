import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../../core/theme.dart';
import '../../data/models/client.dart';
import '../../data/models/order.dart' as model;
import '../../data/models/prescription.dart';
import '../../data/repositories/clients_repo.dart';
import '../../data/repositories/orders_repo.dart';
import '../../data/repositories/prescriptions_repo.dart';
import 'recommendation_engine.dart';

class ReportScreen extends ConsumerWidget {
  final String orderId;
  const ReportScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderByIdProvider(orderId));
    return Scaffold(
      appBar: AppBar(
        title: Text('Reporte · ${orderId.substring(0, 8)}'),
        actions: [
          IconButton(
            tooltip: 'Imprimir',
            onPressed: () async {
              final order = await ref.read(orderByIdProvider(orderId).future);
              if (order == null) return;
              final client = await ref.read(clientByIdProvider(order.clientId).future);
              final rxs = await ref.read(rxByClientProvider(order.clientId).future);
              final rx = rxs.isNotEmpty
                  ? rxs.first
                  : Prescription(
                      clinicId: order.clinicId,
                      clientId: order.clientId,
                      takenAt: order.orderDate);
              await Printing.layoutPdf(
                onLayout: (format) => _buildPdf(format, order, client, rx),
              );
            },
            icon: const Icon(Icons.print),
          ),
        ],
      ),
      body: orderAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (o) {
          if (o == null) return const Center(child: Text('Orden no encontrada.'));
          return Consumer(builder: (ctx, ref, _) {
            final client = ref.watch(clientByIdProvider(o.clientId));
            final rxAsync = ref.watch(rxByClientProvider(o.clientId));
            return ListView(padding: const EdgeInsets.all(20), children: [
              _headerBanner(o, client.value),
              const SizedBox(height: 16),
              _kv('Folio', o.folio, mono: true),
              _kv('Fecha', DateFormat('dd MMM yyyy').format(o.orderDate)),
              _kv('Total', '\$${o.cost.toStringAsFixed(2)}', mono: true),
              _kv('Forma pago', o.payForm),
              _kv('Enganche', '\$${o.downPayment.toStringAsFixed(2)}'),
              _kv('Pago semanal', '\$${o.weeklyPayment.toStringAsFixed(2)}'),
              if (o.deliveryDate != null)
                _kv('Entrega', DateFormat('dd/MM/yyyy').format(o.deliveryDate!)),
              const Divider(height: 24),
              _kv('Modelo', o.frameModel ?? '–'),
              _kv('Color', o.frameColor ?? '–'),
              _kv('Material', o.material ?? '–'),
              _kv('Diseño', o.design ?? '–'),
              _kv('Tratamiento', o.arCoating ?? '–'),
              if (o.photochromic) _kv('Fotocromático', 'Sí'),
              const Divider(height: 24),
              _kv('Laboratorio', o.labName ?? '–'),
              _kv('Folio lab', o.labFolio ?? '–'),
              const SizedBox(height: 16),
              rxAsync.maybeWhen(
                data: (rxs) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _recommendationCard(rxs, client.value),
                      const SizedBox(height: 16),
                      _rxProgressionCard(rxs),
                    ]),
                orElse: () => const SizedBox.shrink(),
              ),
            ]);
          });
        },
      ),
    );
  }

  Widget _headerBanner(model.Order o, Client? c) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [AppColors.greenPrimary, AppColors.navy]),
            borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('SALUD VISUAL · Reporte Cliente',
              style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(c?.fullName ?? 'Cliente',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800)),
          Text('Folio ${o.folio}',
              style: const TextStyle(
                  color: Colors.white, fontFamily: 'DMMono')),
        ]),
      );

  Widget _kv(String k, String v, {bool mono = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          SizedBox(
              width: 140,
              child: Text(k,
                  style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600))),
          Expanded(
              child: Text(v,
                  style: TextStyle(
                      fontFamily: mono ? 'DMMono' : null,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink))),
        ]),
      );

  Widget _recommendationCard(List<Prescription> rxs, Client? c) {
    if (rxs.isEmpty) return const SizedBox.shrink();
    final last = rxs.first;
    final rec = RecommendationEngine.forRx(
      odEsf: last.odEsf, oiEsf: last.oiEsf,
      odAdd: last.odAdd, oiAdd: last.oiAdd,
      age: c?.age ?? 30,
      diabetes: c?.diabetes ?? false,
    );
    return Card(
      color: AppColors.greenMist,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.auto_awesome, color: AppColors.greenPrimary, size: 18),
            SizedBox(width: 6),
            Text('Recomendación clínica',
                style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy)),
          ]),
          const Divider(height: 16),
          Wrap(spacing: 8, runSpacing: 6, children: [
            _pill('Material', rec.material),
            _pill('Diseño', rec.design),
            _pill('AR', rec.arCoating),
            if (rec.photochromicSuggested) _pill('Fotocromático', 'Sí'),
          ]),
          const SizedBox(height: 8),
          Text('Armazón sugerido: ${rec.frameShapes.join(', ')}',
              style: const TextStyle(fontSize: 12, color: AppColors.mid)),
          const SizedBox(height: 8),
          ...rec.reasons.map((r) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Icon(Icons.check, size: 14, color: AppColors.greenPrimary),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(r,
                          style: const TextStyle(fontSize: 12, color: AppColors.mid))),
                ]),
              )),
        ]),
      ),
    );
  }

  Widget _pill(String k, String v) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.greenAccent, width: 1),
        ),
        child: Text('$k · $v',
            style: const TextStyle(
                fontFamily: 'DMMono',
                fontWeight: FontWeight.w700,
                color: AppColors.navy,
                fontSize: 12)),
      );

  Widget _rxProgressionCard(List<Prescription> rxs) {
    if (rxs.length < 2) return const SizedBox.shrink();
    final history = List<Prescription>.from(rxs.reversed); // oldest -> newest
    final maxAbs = history
        .map((p) => [p.odEsf, p.oiEsf].whereType<double>().map((v) => v.abs()).fold<double>(0, (a, b) => a > b ? a : b))
        .fold<double>(0.5, (a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Progresión de la graduación (ESF)',
              style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.navy)),
          const SizedBox(height: 8),
          SizedBox(
              height: 140,
              child: CustomPaint(
                size: const Size(double.infinity, 140),
                painter: _RxChartPainter(history, maxAbs),
              )),
          const SizedBox(height: 6),
          Row(children: [
            _legend(AppColors.greenPrimary, 'OD'),
            const SizedBox(width: 12),
            _legend(AppColors.navy, 'OI'),
          ]),
        ]),
      ),
    );
  }

  Widget _legend(Color c, String text) => Row(children: [
        Container(width: 10, height: 10, color: c),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
      ]);

  /// Pdf rendering — brand green/navy.
  Future<Uint8List> _buildPdf(PdfPageFormat format, model.Order o,
      Client? c, Prescription rx) async {
    final pdf = pw.Document();
    PdfColor green = const PdfColor.fromInt(0xFF1A7A4A);
    PdfColor navy = const PdfColor.fromInt(0xFF1E3A5F);
    PdfColor light = const PdfColor.fromInt(0xFFF0FBF5);

    pw.Widget kv(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(children: [
            pw.SizedBox(
                width: 110,
                child: pw.Text(k,
                    style: const pw.TextStyle(
                        color: PdfColors.grey700, fontSize: 9))),
            pw.Expanded(
                child: pw.Text(v,
                    style: pw.TextStyle(
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 10))),
          ]),
        );

    pw.Widget rxRow(String eye, dynamic esf, dynamic cil, dynamic eje,
        dynamic add, dynamic dip, dynamic alt) {
      pw.Widget cell(String t) => pw.Expanded(
          child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              alignment: pw.Alignment.center,
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400, width: .5)),
              child: pw.Text(t,
                  style: const pw.TextStyle(fontSize: 9))));
      return pw.Row(children: [
        pw.Container(
            width: 30,
            padding: const pw.EdgeInsets.symmetric(vertical: 3),
            alignment: pw.Alignment.center,
            decoration: pw.BoxDecoration(color: light),
            child: pw.Text(eye,
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10))),
        cell(esf?.toString() ?? '–'),
        cell(cil?.toString() ?? '–'),
        cell(eje?.toString() ?? '–'),
        cell(add?.toString() ?? '–'),
        cell(dip?.toString() ?? '–'),
        cell(alt?.toString() ?? '–'),
      ]);
    }

    pdf.addPage(pw.Page(
      pageFormat: format,
      build: (ctx) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.stretch, children: [
        // Banner
        pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(color: green),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('SALUD VISUAL',
                  style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold)),
              pw.Text('Servicios de Salud Óptica · Reporte Cliente',
                  style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
            ])),
        pw.SizedBox(height: 10),
        pw.Row(children: [
          pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(c?.fullName ?? 'Cliente',
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: navy)),
            pw.Text('Folio: ${o.folio}',
                style: const pw.TextStyle(fontSize: 10)),
            pw.Text('Fecha: ${DateFormat('dd/MM/yyyy').format(o.orderDate)}',
                style: const pw.TextStyle(fontSize: 10)),
          ])),
          pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: pw.BoxDecoration(color: light),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                pw.Text('TOTAL', style: const pw.TextStyle(fontSize: 8)),
                pw.Text('\$${o.cost.toStringAsFixed(2)}',
                    style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: green)),
              ])),
        ]),
        pw.SizedBox(height: 12),
        pw.Text('Graduación Rx',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: navy)),
        pw.SizedBox(height: 4),
        pw.Row(children: [
          pw.SizedBox(width: 30),
          ...['ESF', 'CIL', 'EJE', 'ADD', 'DIP', 'ALT']
              .map((h) => pw.Expanded(
                  child: pw.Center(
                      child: pw.Text(h,
                          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700))))),
        ]),
        rxRow('OD', rx.odEsf, rx.odCil, rx.odEje, rx.odAdd, rx.odDip, rx.odAlt),
        rxRow('OI', rx.oiEsf, rx.oiCil, rx.oiEje, rx.oiAdd, rx.oiDip, rx.oiAlt),
        pw.SizedBox(height: 12),
        pw.Text('Armazón y Lentes',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: navy)),
        pw.SizedBox(height: 4),
        kv('Modelo', o.frameModel ?? '–'),
        kv('Color', o.frameColor ?? '–'),
        kv('Material', o.material ?? '–'),
        kv('Diseño', o.design ?? '–'),
        kv('AR', o.arCoating ?? '–'),
        kv('Fotocromático', o.photochromic ? 'Sí' : 'No'),
        pw.SizedBox(height: 12),
        pw.Text('Pago',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: navy)),
        pw.SizedBox(height: 4),
        kv('Forma', o.payForm),
        kv('Enganche', '\$${o.downPayment.toStringAsFixed(2)}'),
        kv('Pago semanal', '\$${o.weeklyPayment.toStringAsFixed(2)}'),
        if (o.deliveryDate != null)
          kv('Entrega', DateFormat('dd/MM/yyyy').format(o.deliveryDate!)),
        pw.Spacer(),
        pw.Divider(),
        pw.Text('Salud Visual · Documento generado automáticamente.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
      ]),
    ));

    return pdf.save();
  }
}

class _RxChartPainter extends CustomPainter {
  final List<Prescription> history;
  final double maxAbs;
  _RxChartPainter(this.history, this.maxAbs);
  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;
    const padding = 18.0;
    final w = size.width - padding * 2;
    final h = size.height - padding * 2;
    final zero = padding + h / 2;

    // Zero axis
    final axis = Paint()
      ..color = const Color(0xFFD1D5DB)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(padding, zero), Offset(padding + w, zero), axis);

    Offset point(int i, double? v) {
      final x = padding + (history.length == 1 ? w / 2 : (w * i / (history.length - 1)));
      final norm = ((v ?? 0).clamp(-maxAbs, maxAbs)) / maxAbs;
      final y = zero - norm * (h / 2);
      return Offset(x, y);
    }

    void drawLine(double? Function(Prescription) sel, Color color) {
      final paint = Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;
      final path = Path();
      for (var i = 0; i < history.length; i++) {
        final p = point(i, sel(history[i]));
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, paint);
      final dot = Paint()..color = color;
      for (var i = 0; i < history.length; i++) {
        canvas.drawCircle(point(i, sel(history[i])), 3, dot);
      }
    }

    drawLine((p) => p.odEsf, AppColors.greenPrimary);
    drawLine((p) => p.oiEsf, AppColors.navy);
  }

  @override
  bool shouldRepaint(covariant _RxChartPainter old) =>
      old.history.length != history.length;
}
