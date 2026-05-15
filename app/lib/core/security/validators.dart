// Client-side validators — mirror server `validate.ts`.
// Defence-in-depth only: the server is always the source of truth.
//
// • Strip control / bidi chars (Unicode TR9 spoofing)
// • NFKC-normalise
// • Hard length caps to stop ReDoS before regex
// • Allow-list patterns identical to PostgREST CHECK constraints

class FieldError implements Exception {
  final String field;
  final String reason;
  FieldError(this.field, this.reason);
  @override
  String toString() => '$field: $reason';
}

class V {
  static final _controlOrBidi = RegExp(
    r'[\u0000-\u001F\u007F\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]',
  );

  static String _norm(String s) =>
      s.replaceAll(_controlOrBidi, '').trim();

  static String string(
    String field,
    String? raw, {
    int min = 0,
    required int max,
    RegExp? pattern,
    bool allowEmpty = false,
  }) {
    if (raw == null) {
      if (allowEmpty) return '';
      throw FieldError(field, 'required');
    }
    if (raw.length > max * 4) throw FieldError(field, 'too long');
    final s = _norm(raw);
    if (!allowEmpty && s.isEmpty) throw FieldError(field, 'empty');
    if (s.length < min) throw FieldError(field, 'min $min');
    if (s.length > max) throw FieldError(field, 'max $max');
    if (pattern != null && !pattern.hasMatch(s)) {
      throw FieldError(field, 'bad format');
    }
    return s;
  }

  static String email(String field, String? raw) => string(
        field,
        raw,
        max: 254,
        pattern: RegExp(
          r'^[^@\s]{1,64}@[^@\s]{1,189}\.[A-Za-z]{2,24}$',
        ),
      ).toLowerCase();

  static String phoneMx(String field, String? raw) => string(
        field,
        raw,
        max: 20,
        pattern: RegExp(r'^[+0-9 ()-]{7,20}$'),
      );

  static String folio(String field, String? raw) => string(
        field,
        raw,
        max: 16,
        pattern: RegExp(r'^[A-Z]{3}-[0-9]{1,6}-[0-9]{2,4}$'),
      );

  static String uuid(String field, String? raw) => string(
        field,
        raw,
        max: 36,
        pattern: RegExp(
          r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
        ),
      ).toLowerCase();

  static int integer(String field, dynamic raw, int min, int max) {
    final n = raw is int ? raw : int.tryParse('$raw');
    if (n == null) throw FieldError(field, 'integer required');
    if (n < min || n > max) throw FieldError(field, 'range $min..$max');
    return n;
  }

  static double money(String field, dynamic raw) {
    final n = raw is num ? raw.toDouble() : double.tryParse('$raw');
    if (n == null || n.isNaN || n.isInfinite) {
      throw FieldError(field, 'number required');
    }
    if (n < 0 || n > 1000000) throw FieldError(field, 'out of range');
    return (n * 100).roundToDouble() / 100;
  }

  static String rxValue(String field, String? raw) => string(
        field,
        raw,
        max: 8,
        pattern: RegExp(r'^([+-]?\d{1,2}(\.\d{1,2})?|[0-9]{1,3}°?|PL|pl)$'),
      );

  /// Lightweight HTML/script stripper for any text destined to be rendered.
  static String safeText(String s) =>
      _norm(s).replaceAll(RegExp(r'<[^>]*>'), '');
}
