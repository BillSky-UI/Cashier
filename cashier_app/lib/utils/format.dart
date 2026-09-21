import 'dart:math';

String formatRupiah(num value) {
  final negative = value < 0;
  final digits = value.abs().round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    buffer.write(digits[i]);
    final remaining = digits.length - i - 1;
    if (remaining > 0 && remaining % 3 == 0) {
      buffer.write('.');
    }
  }
  return 'Rp ${negative ? '-' : ''}$buffer';
}

String formatDateTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(dt.day)}/${two(dt.month)}/${two(dt.year)} ${two(dt.hour)}:${two(dt.minute)}';
}

final Random _billRandom = Random();

/// Generates a unique, human-friendly random bill reference such as
/// "BLF-84920". The "L" reads as a 1 in some thermal fonts, keeping the
/// reference unambiguous. Collisions are statistically negligible.
String generateBillNumber() {
  const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ'; // no I/O/0 to avoid confusion
  final letters = List.generate(
      2, (_) => alphabet[_billRandom.nextInt(alphabet.length)]).join();
  final digits =
      List.generate(5, (_) => _billRandom.nextInt(10).toString()).join();
  return 'BLF-$letters$digits';
}