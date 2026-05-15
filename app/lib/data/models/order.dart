class Order {
  final String? id;
  final String clinicId;
  final String clientId;
  final String? prescriptionId;
  final String folio;
  final DateTime orderedOn;

  // Frame & lens
  final String? frameModel;
  final String? frameColor;
  final double? aroMm;
  final double? puenteMm;
  final double? varillaMm;
  final String? material; // BLANCO | POLI | HI
  final String? design;   // MONO | BIFOCAL | PROGRESIVO
  final String? ar;       // NO | AR | AR_BLUE
  final bool photochromic;
  final String? filter;

  // Payment
  final double cost;
  final String payForm; // CONTADO | CREDITO
  final double downPayment;
  final double weeklyPayment;
  final DateTime? deliveryDate;
  final String? payDay;

  // Lab
  final String? lab;
  final String? labFolio;
  final double? costMicas;
  final double? costBisel;
  final double? costMaq;

  const Order({
    this.id,
    required this.clinicId,
    required this.clientId,
    this.prescriptionId,
    required this.folio,
    required this.orderedOn,
    this.frameModel, this.frameColor,
    this.aroMm, this.puenteMm, this.varillaMm,
    this.material, this.design, this.ar, this.photochromic = false, this.filter,
    required this.cost,
    this.payForm = 'CONTADO',
    this.downPayment = 0,
    this.weeklyPayment = 0,
    this.deliveryDate,
    this.payDay,
    this.lab, this.labFolio,
    this.costMicas, this.costBisel, this.costMaq,
  });

  // UI back-compat aliases
  DateTime get orderDate => orderedOn;
  double? get pteMm => puenteMm;
  double? get varMm => varillaMm;
  String? get arCoating => ar;
  String? get labName => lab;

  factory Order.fromMap(Map<String, dynamic> m) => Order(
        id: m['id'] as String?,
        clinicId: m['clinic_id'] as String,
        clientId: m['client_id'] as String,
        prescriptionId: m['prescription_id'] as String?,
        folio: m['folio'] as String,
        orderedOn: DateTime.parse(m['ordered_on'].toString()),
        frameModel: m['frame_model'] as String?,
        frameColor: m['frame_color'] as String?,
        aroMm: (m['aro_mm'] as num?)?.toDouble(),
        puenteMm: (m['puente_mm'] as num?)?.toDouble(),
        varillaMm: (m['varilla_mm'] as num?)?.toDouble(),
        material: m['material'] as String?,
        design: m['design'] as String?,
        ar: m['ar'] as String?,
        photochromic: (m['photochromic'] as bool?) ?? false,
        filter: m['filter'] as String?,
        cost: (m['cost'] as num?)?.toDouble() ?? 0,
        payForm: (m['pay_form'] as String?) ?? 'CONTADO',
        downPayment: (m['down_payment'] as num?)?.toDouble() ?? 0,
        weeklyPayment: (m['weekly_payment'] as num?)?.toDouble() ?? 0,
        deliveryDate: m['delivery_date'] != null
            ? DateTime.tryParse(m['delivery_date'].toString())
            : null,
        payDay: m['pay_day'] as String?,
        lab: m['lab'] as String?,
        labFolio: m['lab_folio'] as String?,
        costMicas: (m['cost_micas'] as num?)?.toDouble(),
        costBisel: (m['cost_bisel'] as num?)?.toDouble(),
        costMaq: (m['cost_maq'] as num?)?.toDouble(),
      );

  Map<String, dynamic> toInsert() => {
        'clinic_id': clinicId,
        'client_id': clientId,
        if (prescriptionId != null) 'prescription_id': prescriptionId,
        'folio': folio,
        'ordered_on': orderedOn.toIso8601String().substring(0, 10),
        if (frameModel != null) 'frame_model': frameModel,
        if (frameColor != null) 'frame_color': frameColor,
        if (aroMm != null) 'aro_mm': aroMm,
        if (puenteMm != null) 'puente_mm': puenteMm,
        if (varillaMm != null) 'varilla_mm': varillaMm,
        if (material != null) 'material': material,
        if (design != null) 'design': design,
        if (ar != null) 'ar': ar,
        'photochromic': photochromic,
        if (filter != null) 'filter': filter,
        'cost': cost,
        'pay_form': payForm,
        'down_payment': downPayment,
        'weekly_payment': weeklyPayment,
        if (deliveryDate != null)
          'delivery_date': deliveryDate!.toIso8601String().substring(0, 10),
        if (payDay != null) 'pay_day': payDay,
        if (lab != null) 'lab': lab,
        if (labFolio != null) 'lab_folio': labFolio,
        if (costMicas != null) 'cost_micas': costMicas,
        if (costBisel != null) 'cost_bisel': costBisel,
        if (costMaq != null) 'cost_maq': costMaq,
      };
}
