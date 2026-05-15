import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/security/form_v.dart';
import '../../core/theme.dart';
import '../../data/models/client.dart';
import '../../data/models/order.dart' as model;
import '../../data/models/prescription.dart';
import '../../data/providers/supabase_provider.dart';
import '../../data/repositories/clients_repo.dart';
import '../../data/repositories/orders_repo.dart';

/// Nueva Orden — Flutter port of the Salud Visual HTML order form.
/// Reads any pre-filled scanner extraction from `extractedReceiptProvider`.
class NewOrderScreen extends ConsumerStatefulWidget {
  const NewOrderScreen({super.key});
  @override
  ConsumerState<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends ConsumerState<NewOrderScreen> {
  final _formKey = GlobalKey<FormState>();

  // Cliente
  final _name = TextEditingController();
  final _age = TextEditingController();
  String _sex = 'F';
  final _phone = TextEditingController();
  final _street = TextEditingController();
  final _between = TextEditingController();
  final _colonia = TextEditingController();
  final _municipio = TextEditingController();
  final _reference = TextEditingController();
  bool _diabetes = false;
  bool _hypertension = false;

  // Rx grid — OD/OI × ESF, CIL, EJE, ADD, DIP, ALT
  final Map<String, TextEditingController> _rx = {
    for (final eye in const ['OD', 'OI'])
      for (final col in const ['ESF', 'CIL', 'EJE', 'ADD', 'DIP', 'ALT'])
        '$eye-$col': TextEditingController(),
  };

  // Anterior / Actual
  final _antOd = TextEditingController();
  final _antOi = TextEditingController();
  final _actOd = TextEditingController();
  final _actOi = TextEditingController();

  // Armazón
  final _frameModel = TextEditingController();
  final _frameColor = TextEditingController();
  final _aro = TextEditingController();
  final _pte = TextEditingController();
  final _vart = TextEditingController();
  String _material = 'BLANCO';
  String _design = 'MONO';
  String _ar = 'NO';
  bool _photo = false;

  // Pago
  final _cost = TextEditingController();
  String _payForm = 'CONTADO';
  final _down = TextEditingController(text: '0');
  final _weekly = TextEditingController(text: '0');
  DateTime? _delivery;
  String _payDay = 'LUN';

  // Lab
  final _labFolio = TextEditingController();
  final _costMicas = TextEditingController();
  final _costBisel = TextEditingController();
  final _costMaq = TextEditingController();

  String? _folio;
  bool _busy = false;
  bool _prefilled = false;

  @override
  void dispose() {
    for (final c in [
      _name, _age, _phone, _street, _between, _colonia, _municipio,
      _reference, _antOd, _antOi, _actOd, _actOi, _frameModel, _frameColor,
      _aro, _pte, _vart, _cost, _down, _weekly, _labFolio,
      _costMicas, _costBisel, _costMaq
    ]) {
      c.dispose();
    }
    for (final c in _rx.values) {
      c.dispose();
    }
    super.dispose();
  }

  // Edge function returns: nombre, tel, edad, calle, entre, colonia, municipio, ref,
  // od_esf, od_cyl, od_eje, od_add, oi_esf, oi_cyl, oi_eje, oi_add, dip, alt,
  // ant_od, ant_oi, act_od, act_oi, armazon, medidas, material, diseno, tipo_vision,
  // foto, ar, diab, pres, costo, anticipo, fpago, semanal, entrega, lab_folio.
  void _applyExtraction(Map<String, dynamic> e) {
    String s(dynamic v) => v?.toString().trim() ?? '';
    void txt(TextEditingController c, dynamic v) {
      final str = s(v); if (str.isNotEmpty) c.text = str;
    }
    void setRx(String key, dynamic v) {
      final str = s(v); if (str.isNotEmpty && _rx.containsKey(key)) _rx[key]!.text = str;
    }

    // Cliente
    txt(_name,      e['nombre']    ?? e['client_name'] ?? e['name']);
    txt(_phone,     e['tel']       ?? e['phone']);
    txt(_age,       e['edad']);
    txt(_street,    e['calle']     ?? e['street']);
    txt(_between,   e['entre']     ?? e['between']);
    txt(_colonia,   e['colonia']);
    txt(_municipio, e['municipio']);
    txt(_reference, e['ref']       ?? e['reference']);
    if (e['diab'] == true) _diabetes = true;
    if (e['pres'] == true) _hypertension = true;

    // Rx — flat keys from edge function
    setRx('OD-ESF', e['od_esf']); setRx('OD-CIL', e['od_cyl'] ?? e['od_cil']);
    setRx('OD-EJE', e['od_eje']); setRx('OD-ADD', e['od_add']);
    setRx('OD-DIP', e['dip']);    setRx('OD-ALT', e['alt']);
    setRx('OI-ESF', e['oi_esf']); setRx('OI-CIL', e['oi_cyl'] ?? e['oi_cil']);
    setRx('OI-EJE', e['oi_eje']); setRx('OI-ADD', e['oi_add']);
    // nested od/oi objects (forward compat)
    final od = e['od'] as Map?, oi = e['oi'] as Map?;
    if (od != null) {
      setRx('OD-ESF', od['esf']); setRx('OD-CIL', od['cil'] ?? od['cyl']);
      setRx('OD-EJE', od['eje']); setRx('OD-ADD', od['add']);
      setRx('OD-DIP', od['dip']); setRx('OD-ALT', od['alt']);
    }
    if (oi != null) {
      setRx('OI-ESF', oi['esf']); setRx('OI-CIL', oi['cil'] ?? oi['cyl']);
      setRx('OI-EJE', oi['eje']); setRx('OI-ADD', oi['add']);
    }

    // Lecturas anteriores / actuales
    txt(_antOd, e['ant_od'] ?? e['antOd']);
    txt(_antOi, e['ant_oi'] ?? e['antOi']);
    txt(_actOd, e['act_od'] ?? e['actOd']);
    txt(_actOi, e['act_oi'] ?? e['actOi']);

    // Armazón
    txt(_frameModel, e['armazon']    ?? e['frame_model'] ?? e['frame']);
    txt(_frameColor, e['medidas']    ?? e['frame_color'] ?? e['color']);

    // Material
    final mat = (e['material'] as String? ?? '').toUpperCase();
    if (['BLANCO', 'POLI', 'HI'].contains(mat)) _material = mat;

    // Diseño — AI uses 'diseno' (INVISIBLE=bifocal) and 'tipo_vision'
    final dis = ((e['diseno'] ?? e['tipo_vision'] ?? e['design']) as String? ?? '').toUpperCase();
    if (dis.contains('PROG'))    _design = 'PROGRESIVO';
    else if (dis == 'BIFOCAL' || dis == 'INVISIBLE') _design = 'BIFOCAL';
    else if (dis == 'MONO')      _design = 'MONO';

    // AR
    final ar = (e['ar'] as String? ?? '').toUpperCase();
    if (ar == 'AR_BLUE') _ar = 'AR_BLUE';
    else if (ar == 'AR') _ar = 'AR';

    // Fotocromático
    if (e['foto'] == true) _photo = true;

    // Pago
    txt(_cost,   e['costo']   ?? e['cost']);
    txt(_down,   e['anticipo'] ?? e['down']);
    txt(_weekly, e['semanal']  ?? e['weekly']);
    final fp = (e['fpago'] ?? e['payForm'] ?? '').toString().toUpperCase();
    if (fp == 'CREDITO') _payForm = 'CREDITO';
    else if (fp == 'CONTADO') _payForm = 'CONTADO';

    // Lab folio
    txt(_labFolio, e['lab_folio'] ?? e['labFolio']);
  }

  Future<String> _ensureFolio() async {
    if (_folio != null) return _folio!;
    final m = await ref.read(membershipProvider.future);
    final f = await ref.read(ordersRepoProvider).nextFolio(m?.clinicId ?? '');
    if (mounted) setState(() => _folio = f);
    return f;
  }

  double _d(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;
  int? _i(TextEditingController c) => int.tryParse(c.text.trim());
  double? _od(TextEditingController c) {
    if (c.text.trim().isEmpty) return null;
    return double.tryParse(c.text.trim().replaceAll(',', '.'));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final m = await ref.read(membershipProvider.future);
      if (m == null) throw StateError('Sin clínica activa.');
      final folio = await _ensureFolio();

      final client = Client(
        id: '',
        clinicId: m.clinicId,
        name: _name.text.trim(),
        age: _i(_age),
        phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        street: _street.text.trim().isEmpty ? null : _street.text.trim(),
        between:
            _between.text.trim().isEmpty ? null : _between.text.trim(),
        colonia: _colonia.text.trim().isEmpty ? null : _colonia.text.trim(),
        municipio:
            _municipio.text.trim().isEmpty ? null : _municipio.text.trim(),
        reference:
            _reference.text.trim().isEmpty ? null : _reference.text.trim(),
        diabetes: _diabetes,
        hypertension: _hypertension,
      );
      final savedClient = await ref.read(clientsRepoProvider).insert(client);

      final order = model.Order(
        clinicId: m.clinicId,
        clientId: savedClient.id,
        folio: folio,
        orderedOn: DateTime.now(),
        frameModel:
            _frameModel.text.trim().isEmpty ? null : _frameModel.text.trim(),
        frameColor:
            _frameColor.text.trim().isEmpty ? null : _frameColor.text.trim(),
        aroMm: _od(_aro),
        puenteMm: _od(_pte),
        varillaMm: _od(_vart),
        material: _material,
        design: _design,
        ar: _ar,
        photochromic: _photo,
        cost: _d(_cost),
        payForm: _payForm,
        downPayment: _d(_down),
        weeklyPayment: _d(_weekly),
        deliveryDate: _delivery,
        payDay: _payDay,
        lab: m.clinicName,
        labFolio:
            _labFolio.text.trim().isEmpty ? null : _labFolio.text.trim(),
        costMicas: _od(_costMicas),
        costBisel: _od(_costBisel),
        costMaq: _od(_costMaq),
      );
      final rx = Prescription(
        clinicId: m.clinicId,
        clientId: savedClient.id,
        takenAt: DateTime.now(),
        odEsf: _od(_rx['OD-ESF']!), odCyl: _od(_rx['OD-CIL']!),
        odEje: _i(_rx['OD-EJE']!),  odAdd: _od(_rx['OD-ADD']!),
        oiEsf: _od(_rx['OI-ESF']!), oiCyl: _od(_rx['OI-CIL']!),
        oiEje: _i(_rx['OI-EJE']!),  oiAdd: _od(_rx['OI-ADD']!),
        dip: _od(_rx['OD-DIP']!),   alt: _od(_rx['OD-ALT']!),
        antOd: _od(_antOd), antOi: _od(_antOi),
        actOd: _od(_actOd), actOi: _od(_actOi),
      );

      final saved = await ref.read(ordersRepoProvider).createWithRx(order, rx);
      if (!mounted) return;
      ref.read(extractedReceiptProvider.notifier).state = null;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Orden $folio guardada.')));
      context.go('/report/${saved.id}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.danger));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ref.listen fires whenever the provider value changes — handles widget reuse.
    ref.listen<Map<String, dynamic>?>(extractedReceiptProvider, (prev, next) {
      if (next != null && next != prev) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() { _prefilled = true; _applyExtraction(next); });
        });
      } else if (next == null) {
        _prefilled = false;
      }
    });

    final extraction = ref.watch(extractedReceiptProvider);
    // Initial check: provider already set when widget was first built (fresh instance).
    if (extraction != null && !_prefilled) {
      _prefilled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _applyExtraction(extraction));
      });
    }
    if (_folio == null && !_busy) {
      _ensureFolio();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: Form(
          key: _formKey,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _header(),
            const SizedBox(height: 12),
            if (extraction != null)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                    color: AppColors.greenSoft,
                    borderRadius: BorderRadius.circular(8)),
                child: const Row(children: [
                  Icon(Icons.auto_awesome,
                      size: 18, color: AppColors.greenPrimary),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Campos prellenados desde el Escáner IA. Verifica antes de guardar.',
                      style: TextStyle(
                          color: AppColors.greenPrimary,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ]),
              ),
            _section('Datos del Cliente', _clientSection()),
            _section('Graduación Rx', _rxSection()),
            _section('Anterior / Actual', _readingsSection()),
            _section('Armazón y Lentes', _frameSection()),
            _section('Pago', _paymentSection()),
            _section('Laboratorio', _labSection()),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: extraction != null
                    ? OutlinedButton.icon(
                        onPressed: _busy ? null : () {
                          ref.read(extractedReceiptProvider.notifier).state = null;
                          context.go('/scanner');
                        },
                        icon: const Icon(Icons.close),
                        label: const Text('Cancelar'),
                      )
                    : OutlinedButton.icon(
                        onPressed: _busy ? null : () => _formKey.currentState?.reset(),
                        icon: const Icon(Icons.refresh),
                        label: const Text('Limpiar'),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _save,
                  icon: _busy
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save),
                  label: const Text('Guardar Orden'),
                ),
              ),
            ]),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [AppColors.greenPrimary, AppColors.greenAccent]),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          const Icon(Icons.add_circle, color: Colors.white),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Nueva Orden',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: Colors.white24, borderRadius: BorderRadius.circular(20)),
            child: Text(
              _folio ?? '…',
              style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'DMMono',
                  fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      );

  Widget _section(String title, Widget body) => Card(
        margin: const EdgeInsets.only(top: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy)),
            const Divider(height: 16),
            body,
          ]),
        ),
      );

  Widget _grid(List<Widget> children, {int cols = 3}) =>
      LayoutBuilder(builder: (ctx, c) {
        final n = c.maxWidth < 520 ? 1 : (c.maxWidth < 900 ? 2 : cols);
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: children
              .map((w) =>
                  SizedBox(width: (c.maxWidth - 10 * (n - 1)) / n, child: w))
              .toList(),
        );
      });

  Widget _t(TextEditingController c, String label,
          {TextInputType? kb,
          String? Function(String?)? validator,
          List<TextInputFormatter>? formatters}) =>
      TextFormField(
        controller: c,
        keyboardType: kb,
        inputFormatters: formatters,
        decoration: InputDecoration(labelText: label, isDense: true),
        validator: validator,
      );

  Widget _clientSection() => _grid([
        _t(_name, 'Nombre completo *', validator: FormV.required('Nombre')),
        _t(_age, 'Edad',
            kb: TextInputType.number,
            validator: (v) => FormV.integer(v, min: 0, max: 130)),
        DropdownButtonFormField<String>(
          initialValue: _sex,
          decoration:
              const InputDecoration(labelText: 'Sexo', isDense: true),
          items: const [
            DropdownMenuItem(value: 'F', child: Text('Femenino')),
            DropdownMenuItem(value: 'M', child: Text('Masculino')),
            DropdownMenuItem(value: 'X', child: Text('Otro / no especifica')),
          ],
          onChanged: (v) => setState(() => _sex = v ?? 'F'),
        ),
        _t(_phone, 'Teléfono',
            kb: TextInputType.phone, validator: FormV.phoneOptional),
        _t(_street, 'Calle'),
        _t(_between, 'Entre calles'),
        _t(_colonia, 'Colonia'),
        _t(_municipio, 'Municipio'),
        _t(_reference, 'Referencia'),
        Row(children: [
          Expanded(
              child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _diabetes,
            onChanged: (v) => setState(() => _diabetes = v),
            title: const Text('Diabetes', style: TextStyle(fontSize: 13)),
          )),
          Expanded(
              child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _hypertension,
            onChanged: (v) => setState(() => _hypertension = v),
            title:
                const Text('Hipertensión', style: TextStyle(fontSize: 13)),
          )),
        ]),
      ]);

  Widget _rxSection() {
    const cols = ['ESF', 'CIL', 'EJE', 'ADD', 'DIP', 'ALT'];
    Widget row(String eye) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            SizedBox(
                width: 38,
                child: Text(eye,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontFamily: 'DMMono'))),
            for (final c in cols)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: _t(_rx['$eye-$c']!, c,
                      validator: c == 'EJE'
                          ? (v) => FormV.integer(v, min: 0, max: 180)
                          : FormV.rx),
                ),
              ),
          ]),
        );
    return Column(children: [row('OD'), row('OI')]);
  }

  Widget _readingsSection() => _grid([
        _t(_antOd, 'Anterior OD', validator: FormV.rx),
        _t(_antOi, 'Anterior OI', validator: FormV.rx),
        _t(_actOd, 'Actual OD', validator: FormV.rx),
        _t(_actOi, 'Actual OI', validator: FormV.rx),
      ], cols: 4);

  Widget _frameSection() => _grid([
        _t(_frameModel, 'Modelo'),
        _t(_frameColor, 'Color'),
        _t(_aro, 'ARO (mm)', kb: TextInputType.number),
        _t(_pte, 'PTE (mm)', kb: TextInputType.number),
        _t(_vart, 'VAR (mm)', kb: TextInputType.number),
        DropdownButtonFormField<String>(
          initialValue: _material,
          decoration:
              const InputDecoration(labelText: 'Material', isDense: true),
          items: const [
            DropdownMenuItem(value: 'BLANCO', child: Text('Blanco (CR-39)')),
            DropdownMenuItem(value: 'POLI', child: Text('Policarbonato')),
            DropdownMenuItem(value: 'HI', child: Text('Alto Índice')),
          ],
          onChanged: (v) => setState(() => _material = v ?? 'BLANCO'),
        ),
        DropdownButtonFormField<String>(
          initialValue: _design,
          decoration:
              const InputDecoration(labelText: 'Diseño', isDense: true),
          items: const [
            DropdownMenuItem(value: 'MONO', child: Text('Monofocal')),
            DropdownMenuItem(value: 'BIFOCAL', child: Text('Bifocal')),
            DropdownMenuItem(value: 'PROGRESIVO', child: Text('Progresivo')),
          ],
          onChanged: (v) => setState(() => _design = v ?? 'MONO'),
        ),
        DropdownButtonFormField<String>(
          initialValue: _ar,
          decoration: const InputDecoration(
              labelText: 'Tratamiento AR', isDense: true),
          items: const [
            DropdownMenuItem(value: 'NO', child: Text('Sin AR')),
            DropdownMenuItem(value: 'AR', child: Text('AR')),
            DropdownMenuItem(value: 'AR_BLUE', child: Text('AR + Blue')),
          ],
          onChanged: (v) => setState(() => _ar = v ?? 'NO'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _photo,
          onChanged: (v) => setState(() => _photo = v),
          title:
              const Text('Fotocromático', style: TextStyle(fontSize: 13)),
        ),
      ]);

  Widget _paymentSection() => _grid([
        _t(_cost, 'Costo total *',
            kb: TextInputType.number,
            validator: (v) => FormV.money(v, allowEmpty: false)),
        DropdownButtonFormField<String>(
          initialValue: _payForm,
          decoration: const InputDecoration(
              labelText: 'Forma de pago', isDense: true),
          items: const [
            DropdownMenuItem(value: 'CONTADO', child: Text('Contado')),
            DropdownMenuItem(value: 'CREDITO', child: Text('Crédito')),
          ],
          onChanged: (v) => setState(() => _payForm = v ?? 'CONTADO'),
        ),
        _t(_down, 'Enganche',
            kb: TextInputType.number, validator: FormV.money),
        _t(_weekly, 'Pago semanal',
            kb: TextInputType.number, validator: FormV.money),
        InkWell(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              firstDate: DateTime.now().subtract(const Duration(days: 1)),
              lastDate: DateTime.now().add(const Duration(days: 365)),
              initialDate:
                  _delivery ?? DateTime.now().add(const Duration(days: 7)),
            );
            if (d != null) setState(() => _delivery = d);
          },
          child: InputDecorator(
            decoration: const InputDecoration(
                labelText: 'Fecha de entrega', isDense: true),
            child: Text(_delivery == null
                ? 'Seleccionar...'
                : DateFormat('dd/MM/yyyy').format(_delivery!)),
          ),
        ),
        DropdownButtonFormField<String>(
          initialValue: _payDay,
          decoration:
              const InputDecoration(labelText: 'Día de pago', isDense: true),
          items: const ['LUN', 'MAR', 'MIE', 'JUE', 'VIE', 'SAB', 'DOM']
              .map((d) => DropdownMenuItem(value: d, child: Text(d)))
              .toList(),
          onChanged: (v) => setState(() => _payDay = v ?? 'LUN'),
        ),
      ]);

  Widget _labSection() {
    final allLabsAsync = ref.watch(allLabsProvider);
    final selectedLab = ref.watch(selectedLabProvider);
    return _grid([
      allLabsAsync.when(
        loading: () => const LinearProgressIndicator(),
        error: (_, __) => const Text('Error cargando laboratorios'),
        data: (labs) {
          final effective = labs.contains(selectedLab)
              ? selectedLab
              : (labs.isNotEmpty ? labs.first : null);
          return DropdownButtonFormField<Membership>(
          key: ValueKey(effective?.clinicId),
          initialValue: effective,
          decoration: const InputDecoration(
              labelText: 'Laboratorio *', isDense: true),
          items: labs
              .map((l) => DropdownMenuItem(value: l, child: Text(l.clinicName)))
              .toList(),
          validator: (v) => v == null ? 'Selecciona un laboratorio' : null,
          onChanged: (lab) {
            if (lab != null) {
              ref.read(selectedLabProvider.notifier).state = lab;
            }
          },
        );
        },
      ),
      _t(_labFolio, 'Folio Lab'),
      _t(_costMicas, 'Costo micas',
          kb: TextInputType.number, validator: FormV.money),
      _t(_costBisel, 'Costo bisel',
          kb: TextInputType.number, validator: FormV.money),
      _t(_costMaq, 'Costo maquila',
          kb: TextInputType.number, validator: FormV.money),
    ]);
  }
}
