class Prescription {
  final String? id;
  final String clinicId;
  final String clientId;
  final DateTime takenAt;

  // Right (OD) / Left (OI). DB uses cyl, app accepts cil alias.
  final double? odEsf, odCyl, odAdd;
  final int? odEje;
  final double? oiEsf, oiCyl, oiAdd;
  final int? oiEje;

  // Shared per-prescription (not per-eye in DB)
  final double? dip;
  final double? alt;

  // Anterior / actual reads
  final double? antOd, antOi, actOd, actOi;

  final String? observations;

  const Prescription({
    this.id,
    required this.clinicId,
    required this.clientId,
    required this.takenAt,
    this.odEsf, this.odCyl, this.odEje, this.odAdd,
    this.oiEsf, this.oiCyl, this.oiEje, this.oiAdd,
    this.dip, this.alt,
    this.antOd, this.antOi, this.actOd, this.actOi,
    this.observations,
  });

  /// Backwards-compat aliases used in the UI / engine.
  double? get odCil => odCyl;
  double? get oiCil => oiCyl;
  double? get odDip => dip;
  double? get oiDip => dip;
  double? get odAlt => alt;
  double? get oiAlt => alt;
  DateTime get visitDate => takenAt;
  String? get notes => observations;

  factory Prescription.fromMap(Map<String, dynamic> m) => Prescription(
        id: m['id'] as String?,
        clinicId: m['clinic_id'] as String,
        clientId: m['client_id'] as String,
        takenAt: DateTime.parse(m['taken_at'].toString()),
        odEsf: (m['od_esf'] as num?)?.toDouble(),
        odCyl: (m['od_cyl'] as num?)?.toDouble(),
        odEje: m['od_eje'] as int?,
        odAdd: (m['od_add'] as num?)?.toDouble(),
        oiEsf: (m['oi_esf'] as num?)?.toDouble(),
        oiCyl: (m['oi_cyl'] as num?)?.toDouble(),
        oiEje: m['oi_eje'] as int?,
        oiAdd: (m['oi_add'] as num?)?.toDouble(),
        dip: (m['dip'] as num?)?.toDouble(),
        alt: (m['alt'] as num?)?.toDouble(),
        antOd: (m['ant_od'] as num?)?.toDouble(),
        antOi: (m['ant_oi'] as num?)?.toDouble(),
        actOd: (m['act_od'] as num?)?.toDouble(),
        actOi: (m['act_oi'] as num?)?.toDouble(),
        observations: m['observations'] as String?,
      );

  Map<String, dynamic> toInsert() => {
        'clinic_id': clinicId,
        'client_id': clientId,
        'taken_at': takenAt.toUtc().toIso8601String(),
        if (odEsf != null) 'od_esf': odEsf,
        if (odCyl != null) 'od_cyl': odCyl,
        if (odEje != null) 'od_eje': odEje,
        if (odAdd != null) 'od_add': odAdd,
        if (oiEsf != null) 'oi_esf': oiEsf,
        if (oiCyl != null) 'oi_cyl': oiCyl,
        if (oiEje != null) 'oi_eje': oiEje,
        if (oiAdd != null) 'oi_add': oiAdd,
        if (dip != null) 'dip': dip,
        if (alt != null) 'alt': alt,
        if (antOd != null) 'ant_od': antOd,
        if (antOi != null) 'ant_oi': antOi,
        if (actOd != null) 'act_od': actOd,
        if (actOi != null) 'act_oi': actOi,
        if (observations != null) 'observations': observations,
      };
}
