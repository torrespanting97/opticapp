class Appointment {
  final String? id;
  final String clinicId;
  final String? clientId;
  final DateTime startsAt;
  final DateTime endsAt;
  final String title;
  final String? notes;
  final String status; // scheduled | confirmed | done | cancelled | no_show
  final String? externalProvider; // 'google' | 'outlook' | null
  final String? externalId;

  const Appointment({
    this.id,
    required this.clinicId,
    this.clientId,
    required this.startsAt,
    required this.endsAt,
    required this.title,
    this.notes,
    this.status = 'scheduled',
    this.externalProvider,
    this.externalId,
  });

  bool get isPast => endsAt.isBefore(DateTime.now());
  bool get isPendingAction =>
      isPast && status != 'done' && status != 'cancelled' && status != 'no_show';

  String get source => switch (externalProvider) {
        'google'  => 'GOOGLE',
        'outlook' => 'OUTLOOK',
        _         => 'INTERNAL',
      };

  Appointment copyWith({
    String? id,
    String? clinicId,
    String? clientId,
    DateTime? startsAt,
    DateTime? endsAt,
    String? title,
    String? notes,
    String? status,
    String? externalProvider,
    String? externalId,
  }) =>
      Appointment(
        id:               id               ?? this.id,
        clinicId:         clinicId         ?? this.clinicId,
        clientId:         clientId         ?? this.clientId,
        startsAt:         startsAt         ?? this.startsAt,
        endsAt:           endsAt           ?? this.endsAt,
        title:            title            ?? this.title,
        notes:            notes            ?? this.notes,
        status:           status           ?? this.status,
        externalProvider: externalProvider ?? this.externalProvider,
        externalId:       externalId       ?? this.externalId,
      );

  factory Appointment.fromMap(Map<String, dynamic> m) => Appointment(
        id:               m['id'] as String?,
        clinicId:         m['clinic_id'] as String,
        clientId:         m['client_id'] as String?,
        startsAt:         DateTime.parse(m['starts_at'].toString()),
        endsAt:           DateTime.parse(m['ends_at'].toString()),
        title:            (m['title'] ?? '') as String,
        notes:            m['notes'] as String?,
        status:           (m['status'] ?? 'scheduled') as String,
        externalProvider: m['external_provider'] as String?,
        externalId:       m['external_id'] as String?,
      );

  Map<String, dynamic> toInsert() => {
        'clinic_id': clinicId,
        if (clientId != null) 'client_id': clientId,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at':   endsAt.toUtc().toIso8601String(),
        'title':     title,
        if (notes != null) 'notes': notes,
        'status':    status,
        if (externalProvider != null) 'external_provider': externalProvider,
        if (externalId != null) 'external_id': externalId,
      };
}
