class Client {
  final String id; // empty string when not yet persisted
  final String clinicId;
  final String name;
  final int? age;
  final String? phone;
  final String? email;
  final String? street;
  final String? between;
  final String? colonia;
  final String? municipio;
  final String? reference;
  final double? lat;
  final double? lng;
  final bool diabetes;
  final bool hypertension;
  final String? notes;
  final String? faceShape;
  final DateTime? createdAt;

  const Client({
    this.id = '',
    required this.clinicId,
    required this.name,
    this.age,
    this.phone,
    this.email,
    this.street,
    this.between,
    this.colonia,
    this.municipio,
    this.reference,
    this.lat,
    this.lng,
    this.diabetes = false,
    this.hypertension = false,
    this.notes,
    this.faceShape,
    this.createdAt,
  });

  /// Backwards-compat alias used across the UI.
  String get fullName => name;

  factory Client.fromMap(Map<String, dynamic> m) => Client(
        id: m['id'] as String,
        clinicId: m['clinic_id'] as String,
        name: (m['name'] ?? '') as String,
        age: m['age'] as int?,
        phone: m['phone'] as String?,
        email: m['email'] as String?,
        street: m['street'] as String?,
        between: m['between'] as String?,
        colonia: m['colonia'] as String?,
        municipio: m['municipio'] as String?,
        reference: m['reference'] as String?,
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        diabetes: (m['diabetes'] as bool?) ?? false,
        hypertension: (m['hypertension'] as bool?) ?? false,
        notes: m['notes'] as String?,
        faceShape: m['face_shape'] as String?,
        createdAt: m['created_at'] != null
            ? DateTime.tryParse(m['created_at'].toString())
            : null,
      );

  Map<String, dynamic> toInsert() => {
        'clinic_id': clinicId,
        'name': name,
        if (age != null) 'age': age,
        if (phone != null) 'phone': phone,
        if (email != null) 'email': email,
        if (street != null) 'street': street,
        if (between != null) 'between': between,
        if (colonia != null) 'colonia': colonia,
        if (municipio != null) 'municipio': municipio,
        if (reference != null) 'reference': reference,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        'diabetes': diabetes,
        'hypertension': hypertension,
        if (notes != null) 'notes': notes,
        if (faceShape != null) 'face_shape': faceShape,
      };
}
