import 'package:flutter/material.dart';

/// Prompts the cashier to enter the 4-digit security PIN and returns true only
/// when the entered PIN passes [verify]. Returns false if cancelled or wrong.
/// Retrying a wrong PIN stays inside this dialog.
Future<bool> promptPin(
  BuildContext context, {
  String title = 'Masukkan PIN Kasir',
  required bool Function(String pin) verify,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PinEntryDialog(title: title, verify: verify),
  ).then((verified) => verified ?? false);
}

class _PinEntryDialog extends StatefulWidget {
  final String title;
  final bool Function(String pin) verify;

  const _PinEntryDialog({required this.title, required this.verify});

  @override
  State<_PinEntryDialog> createState() => _PinEntryDialogState();
}

class _PinEntryDialogState extends State<_PinEntryDialog> {
  String _pin = '';
  String? _error;

  void _onKey(String key) {
    setState(() {
      if (key == 'back') {
        if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1);
        _error = null;
      } else if (key == 'clear') {
        _pin = '';
        _error = null;
      } else if (_pin.length < 4) {
        _pin += key;
        _error = null;
        if (_pin.length == 4) _submit();
      }
    });
  }

  void _submit() {
    if (widget.verify(_pin)) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _pin = '';
        _error = 'PIN salah. Coba lagi.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.lock_outline, color: scheme.primary, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(widget.title,
                style: const TextStyle(fontSize: 18),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 4; i++) ...[
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 46,
                    height: 56,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: i < _pin.length
                            ? scheme.primary
                            : scheme.outlineVariant,
                        width: i < _pin.length ? 2 : 1,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 120),
                      child: i < _pin.length
                          ? Icon(Icons.circle,
                              key: const ValueKey('filled'),
                              size: 14,
                              color: scheme.primary)
                          : Text(
                              '•',
                              key: const ValueKey('empty'),
                              style: TextStyle(
                                  fontSize: 14, color: scheme.outline),
                            ),
                    ),
                  ),
                  if (i < 3) const SizedBox(width: 2),
                ],
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 20,
              child: _error == null
                  ? null
                  : Text(
                      _error!,
                      style: TextStyle(color: scheme.error, fontSize: 13),
                    ),
            ),
            const SizedBox(height: 8),
            _keypad(context),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
      ],
    );
  }

  Widget _keypad(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['C', '0', 'back'],
    ];

    Widget keyWidget(String key) {
      if (key == 'C') {
        return const Text('C',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600));
      }
      if (key == 'back') {
        return const Icon(Icons.backspace, size: 22);
      }
      return Text(key,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600));
    }

    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final key in row)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _onKey(key),
                      child: Container(
                        width: 68,
                        height: 52,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: scheme.outlineVariant),
                        ),
                        alignment: Alignment.center,
                        child: keyWidget(key),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}