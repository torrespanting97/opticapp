class WalletEntry {
  final String id;
  final String clinicId;
  final String clientId;
  final String? orderId;
  final DateTime occurredAt;
  final String kind; // CHARGE | PAYMENT | ADJUST
  final double amount;
  final String? note;
  final String? userId;

  const WalletEntry({
    required this.id,
    required this.clinicId,
    required this.clientId,
    this.orderId,
    required this.occurredAt,
    required this.kind,
    required this.amount,
    this.note,
    this.userId,
  });

  /// UI alias
  DateTime get entryDate => occurredAt;

  factory WalletEntry.fromMap(Map<String, dynamic> m) => WalletEntry(
        id: m['id'] as String,
        clinicId: m['clinic_id'] as String,
        clientId: m['client_id'] as String,
        orderId: m['order_id'] as String?,
        occurredAt: DateTime.parse(m['occurred_at'].toString()),
        kind: m['kind'] as String,
        amount: (m['amount'] as num).toDouble(),
        note: m['note'] as String?,
        userId: m['user_id'] as String?,
      );

  Map<String, dynamic> toInsert() => {
        'clinic_id': clinicId,
        'client_id': clientId,
        if (orderId != null) 'order_id': orderId,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'kind': kind,
        'amount': amount,
        if (note != null) 'note': note,
      };
}

class ClientBalance {
  final String clientId;
  final String clinicId;
  final String fullName;
  final double balance;
  const ClientBalance({
    required this.clientId,
    required this.clinicId,
    required this.fullName,
    required this.balance,
  });
  factory ClientBalance.fromMap(Map<String, dynamic> m) => ClientBalance(
        clientId: m['client_id'] as String,
        clinicId: (m['clinic_id'] ?? '') as String,
        fullName: (m['name'] ?? m['full_name'] ?? '') as String,
        balance: (m['balance'] as num?)?.toDouble() ?? 0,
      );
}
