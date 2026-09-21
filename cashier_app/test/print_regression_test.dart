import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cashier_app/models/transaction.dart';
import 'package:cashier_app/services/thermal_printer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('buildTicket menghasilkan bytes tanpa exception code page', () async {
    final t = Transaction(
      id: 1,
      datetime: DateTime(2026, 9, 6, 10, 0),
      items: [
        TransactionItem(
          productId: 1,
          productName: 'Es Teh Manis',
          quantity: 2,
          price: 5000,
        ),
      ],
      subtotal: 10000,
      total: 10000,
      cashReceived: 10000,
      change: 0,
      paymentMethod: 'cash',
    );

    final bytes = await ThermalPrinter.buildTicket(t);
    expect(bytes, isA<Uint8List>());
    expect(bytes.length, greaterThan(100));
  });
}