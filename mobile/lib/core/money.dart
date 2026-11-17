/// USDT amounts as integers in micro-USDT (6 decimals). No doubles for money.
class Usdt {
  Usdt._();

  static const int decimals = 6;
  static const int micro = 1000000;
  static final RegExp _re = RegExp(r'^(0|[1-9]\d{0,11})(\.\d{1,6})?$');

  /// Parses "12.5" into 12500000. Returns null for invalid input.
  static int? tryParse(String text) {
    final t = text.trim();
    final m = _re.firstMatch(t);
    if (m == null) return null;
    final whole = int.parse(m.group(1)!);
    final fracRaw = (m.group(2) ?? '.').substring(1);
    final frac = fracRaw.padRight(decimals, '0');
    return whole * micro + (frac.isEmpty ? 0 : int.parse(frac));
  }

  /// Formats 99500000 as "99.50".
  static String format(int value, {int minDecimals = 2}) {
    if (value < 0) return '-${format(-value, minDecimals: minDecimals)}';
    final whole = value ~/ micro;
    var frac = (value % micro).toString().padLeft(decimals, '0');
    frac = frac.replaceFirst(RegExp(r'0+$'), '');
    if (frac.length < minDecimals) frac = frac.padRight(minDecimals, '0');
    final w = _groupThousands(whole.toString());
    return frac.isEmpty ? w : '$w.$frac';
  }

  static String _groupThousands(String digits) {
    final buf = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buf.write(',');
      buf.write(digits[i]);
    }
    return buf.toString();
  }
}

String formatDateTime(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  final l = t.toLocal();
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

String shortAddress(String a) =>
    a.length > 14 ? '${a.substring(0, 6)}…${a.substring(a.length - 6)}' : a;
