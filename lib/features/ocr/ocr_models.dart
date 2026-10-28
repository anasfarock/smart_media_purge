enum DocType { receipt, bill, idCard, handwritten, other }

extension DocTypeX on DocType {
  String get label => switch (this) {
        DocType.receipt => 'Receipt',
        DocType.bill => 'Bill',
        DocType.idCard => 'ID card',
        DocType.handwritten => 'Handwritten',
        DocType.other => 'Other',
      };
}

enum SensitiveType { cnic, ssn, creditCard, iban, email, phone, passport }

extension SensitiveTypeX on SensitiveType {
  String get label => switch (this) {
        SensitiveType.cnic => 'National ID',
        SensitiveType.ssn => 'SSN',
        SensitiveType.creditCard => 'Card number',
        SensitiveType.iban => 'IBAN',
        SensitiveType.email => 'Email',
        SensitiveType.phone => 'Phone',
        SensitiveType.passport => 'Passport no.',
      };
}

class SensitiveMatch {
  const SensitiveMatch(this.type, this.start, this.end);
  final SensitiveType type;
  final int start;
  final int end;
}

class DocumentRecord {
  const DocumentRecord({
    this.id = 0,
    required this.assetId,
    required this.modified,
    required this.type,
    required this.body,
    this.merchant,
    this.amount,
    this.date,
    this.sensitiveCount = 0,
  });

  final int id;
  final String assetId;
  final int modified;
  final DocType type;
  final String body;
  final String? merchant;
  final double? amount;
  final DateTime? date;
  final int sensitiveCount;

  Map<String, Object?> toMap() => {
        'asset_id': assetId,
        'modified': modified,
        'doc_type': type.name,
        'body': body,
        'merchant': merchant,
        'amount': amount,
        'doc_date': date?.millisecondsSinceEpoch,
        'sensitive_count': sensitiveCount,
      };

  factory DocumentRecord.fromMap(Map<String, Object?> m) => DocumentRecord(
        id: m['id'] as int,
        assetId: m['asset_id'] as String,
        modified: m['modified'] as int,
        type: DocType.values.firstWhere(
          (t) => t.name == m['doc_type'],
          orElse: () => DocType.other,
        ),
        body: m['body'] as String,
        merchant: m['merchant'] as String?,
        amount: (m['amount'] as num?)?.toDouble(),
        date: m['doc_date'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['doc_date'] as int),
        sensitiveCount: m['sensitive_count'] as int,
      );
}
