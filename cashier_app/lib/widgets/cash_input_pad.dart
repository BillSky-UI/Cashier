import 'package:flutter/material.dart';

import '../utils/format.dart';

/// A self-contained in-app numeric keypad plus quick-cash buttons for entering
/// the cash tendered during payment. It deliberately avoids the system soft
/// keyboard so a cashier can tap through a transaction on a shared / rugged
/// device without keyboard focus issues.
///
/// [amount] holds the raw digits (no separators). [total] is used by the
/// quick "Pas" (exact change) button and to hint the change that would result.
class CashInputPad extends StatelessWidget {
  final double total;
  final String amount;
  final ValueChanged<String> onChanged;

  const CashInputPad({
    super.key,
    required this.total,
    required this.amount,
    required this.onChanged,
  });

  static final _quickAmounts = <String, String>{
    '5k': '5000',
    '10k': '10000',
    '20k': '20000',
    '50k': '50000',
    '100k': '100000',
  };

  String get _display {
    final value = int.tryParse(amount) ?? 0;
    return value == 0 && amount.isEmpty ? '0' : _formatNumber(value);
  }

  double get _entered => int.tryParse(amount)?.toDouble() ?? 0;
  bool get _isExact => amount.isNotEmpty && _entered == total;

  void _append(String digit) {
    if (amount.length >= 9) return;
    onChanged(amount + digit);
  }

  void _backspace() {
    if (amount.isEmpty) return;
    onChanged(amount.substring(0, amount.length - 1));
  }

  void _set(String raw) {
    onChanged(raw);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        // ---- Active amount display + change hint ----
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Uang Tunai',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                'Rp $_display',
                style: const TextStyle(
                    fontSize: 24, fontWeight: FontWeight.bold),
              ),
              if (_entered > 0) ...[
                const SizedBox(height: 4),
                Text(
                  _entered >= total
                      ? 'Kembalian: ${formatRupiah(_entered - total)}'
                      : 'Masih kurang ${formatRupiah(total - _entered)}',
                  style: TextStyle(
                    fontSize: 13,
                    color: _entered >= total ? Colors.green : scheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ---- Quick cash buttons ----
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // Uang Pas -> exactly the total
            _chip(
              context: context,
              label: 'Pas',
              icon: Icons.check_circle_outline,
              selected: _isExact,
              onTap: () => _set(total.round().toString()),
            ),
            for (final e in _quickAmounts.entries)
              _chip(
                context: context,
                label: e.key,
                selected: amount == e.value,
                onTap: () => _set('${int.parse(e.value)}'),
              ),
          ],
        ),
        const SizedBox(height: 16),

        // ---- Keypad grid ----
        Column(
          children: [
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['clear', '0', 'back'],
            ])
              Row(
                children: [
                  for (final key in row)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(3),
                        child: _keypadButton(
                          context,
                          key == 'clear'
                              ? const Icon(Icons.backspace_outlined)
                              : (key == 'back'
                                  ? const Text('C', style: TextStyle(fontSize: 22))
                                  : Text(key,
                                      style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w600))),
                          onTap: () {
                            if (key == 'clear') {
                              // Backspace icon: remove only the last digit.
                              _backspace();
                            } else if (key == 'back') {
                              // "C": clear the entire amount.
                              onChanged('');
                            } else {
                              _append(key);
                            }
                          },
                          aspectRatio: 1,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ],
    );
  }

  Widget _chip({
    required BuildContext context,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
    IconData? icon,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: selected ? scheme.primary : null),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? scheme.onPrimaryContainer : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _keypadButton(BuildContext context, Widget child,
      {required VoidCallback onTap, double? aspectRatio}) {
    return AspectRatio(
      aspectRatio: aspectRatio ?? 1.5,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Center(child: child),
        ),
      ),
    );
  }

  String _formatNumber(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      buffer.write(digits[i]);
      final remaining = digits.length - i - 1;
      if (remaining > 0 && remaining % 3 == 0) buffer.write('.');
    }
    return buffer.toString();
  }
}
