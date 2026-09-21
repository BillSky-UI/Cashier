import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cashier_app/models/category.dart';
import 'package:cashier_app/models/product.dart';
import 'package:cashier_app/models/transaction.dart';
import 'package:cashier_app/utils/format.dart';
import 'package:cashier_app/widgets/receipt_paper.dart';

void main() {
  group('formatRupiah', () {
    test('mengubah angka menjadi format Rupiah', () {
      expect(formatRupiah(0), 'Rp 0');
      expect(formatRupiah(1000), 'Rp 1.000');
      expect(formatRupiah(1500000), 'Rp 1.500.000');
      expect(formatRupiah(123456789), 'Rp 123.456.789');
    });

    test('menangani angka negatif', () {
      expect(formatRupiah(-5000), 'Rp -5.000');
    });
  });

  group('formatDateTime', () {
    test('format tanggal jam', () {
      final dt = DateTime(2026, 9, 2, 8, 5);
      expect(formatDateTime(dt), '02/09/2026 08:05');
    });
  });

  group('generateBillNumber', () {
    test('format BLF-XXXXX and uniqueness', () {
      final a = generateBillNumber();
      final b = generateBillNumber();
      expect(a, startsWith('BLF-'));
      expect(a.length, 11);
      expect(a != b, isTrue);
      expect(RegExp(r'^BLF-[A-Z]{2}\d{5}$').hasMatch(a), isTrue);
    });
  });

  group('Category', () {
    test('round-trip toMap/fromMap', () {
      final cat = Category(id: 3, name: 'Pulsa', orderIndex: 2);
      final map = cat.toMap();
      expect(map['name'], 'Pulsa');
      expect(map['order_index'], 2);
      final restored = Category.fromMap(map);
      expect(restored.id, 3);
      expect(restored.name, 'Pulsa');
      expect(restored.orderIndex, 2);
    });
  });

  group('Product categoryId', () {
    test('persists categoryId in map', () {
      final p = Product(
        id: 1,
        name: 'Paket 5GB',
        price: 50000,
        stock: 10,
        categoryId: 2,
      );
      expect(p.toMap()['category_id'], 2);
      expect(Product.fromMap(p.toMap()).categoryId, 2);
    });
  });

  group('Transaction discount', () {
    test('persists discount and discountLabel in map', () {
      final t = Transaction(
        id: 9,
        datetime: DateTime(2026, 9, 3, 10, 0),
        items: [
          TransactionItem(
            productId: 1,
            productName: 'Pakan Ayam 1kg',
            quantity: 2,
            price: 15000,
          ),
        ],
        subtotal: 30000,
        adminFee: 1000,
        discount: 3000,
        discountLabel: 'Diskon 10%',
        total: 28000,
        cashReceived: 30000,
        change: 2000,
        paymentMethod: 'cash',
      );
      final map = t.toMap();
      expect(map['discount'], 3000);
      expect(map['discount_label'], 'Diskon 10%');
      final restored = Transaction.fromMap(map);
      expect(restored.discount, 3000);
      expect(restored.discountLabel, 'Diskon 10%');
      expect(restored.total, 28000);
    });

    test('product low stock flag', () {
      final low = Product(id: 1, name: 'x', price: 1000, stock: 3);
      final out = Product(id: 2, name: 'y', price: 1000, stock: 0);
      final ok = Product(id: 3, name: 'z', price: 1000, stock: 5);
      expect(low.isLowStock, isTrue);
      expect(low.isOutOfStock, isFalse);
      expect(out.isLowStock, isFalse);
      expect(out.isOutOfStock, isTrue);
      expect(ok.isLowStock, isFalse);
    });
  });

  group('Transaction Payment Point (PPOB)', () {
    Transaction buildBilling() {
      return Transaction(
        id: 8,
        datetime: DateTime(2026, 9, 3, 10, 0),
        items: [
          TransactionItem(
            productId: 0,
            productName: 'Tagihan PLN',
            quantity: 1,
            price: 50000,
            cost: 50000,
          ),
        ],
        subtotal: 50000,
        adminFee: 3000,
        extraAdmin: 500,
        total: 53500,
        cashReceived: 53500,
        change: 0,
        paymentMethod: 'qris',
        type: 'billing',
        billingCategory: 'PLN',
        billingReference: '123456789012',
      );
    }

    test('persists billing fields in toMap/fromMap', () {
      final map = buildBilling().toMap();
      expect(map['type'], 'billing');
      expect(map['billing_category'], 'PLN');
      expect(map['billing_reference'], '123456789012');
      expect(map['extra_admin'], 500);
      final restored = Transaction.fromMap(map);
      expect(restored.isBilling, isTrue);
      expect(restored.billingCategory, 'PLN');
      expect(restored.billingReference, '123456789012');
      expect(restored.extraAdmin, 500);
      expect(restored.total, 53500);
    });

    test('defaults to a regular sale when type is missing', () {
      final map = buildBilling().toMap()..remove('type');
      final restored = Transaction.fromMap(map);
      expect(restored.type, 'sale');
      expect(restored.isBilling, isFalse);
    });

    test('returns the PLN reference label', () {
      final billing = buildBilling();
      expect(billing.billingReferenceLabel, 'Kode Token');
    });

    test('PLN pascabayar uses meter label and type display', () {
      final billing = Transaction(
        datetime: DateTime(2026, 9, 3, 10, 0),
        items: const [],
        subtotal: 50000,
        adminFee: 3000,
        extraAdmin: 500,
        billingFine: 2500,
        total: 56000,
        cashReceived: 56000,
        change: 0,
        paymentMethod: 'qris',
        type: 'billing',
        billingCategory: 'PLN',
        billingSubcategory: 'pascabayar',
        billingReference: '187654321',
      );
      expect(billing.billingReferenceLabel, 'No. Meteran');
      expect(billing.billingTypeDisplay, 'PLN (Pascabayar)');
      final restored = Transaction.fromMap(billing.toMap());
      expect(restored.billingSubcategory, 'pascabayar');
      expect(restored.billingFine, 2500);
      expect(restored.total, 56000);
    });

    testWidgets(
        'billing receipt shows PLN pascabayar rows with fine and meter number',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReceiptPaper(
            transaction: Transaction(
              datetime: DateTime(2026, 9, 3, 10, 0),
              items: [
                TransactionItem(
                  productId: 0,
                  productName: 'Tagihan PLN',
                  quantity: 1,
                  price: 50000,
                  cost: 50000,
                ),
              ],
              subtotal: 50000,
              adminFee: 3000,
              extraAdmin: 500,
              billingFine: 2500,
              total: 56000,
              cashReceived: 56000,
              change: 0,
              paymentMethod: 'qris',
              type: 'billing',
              billingCategory: 'PLN',
              billingSubcategory: 'pascabayar',
              billingReference: '187654321',
            ),
          ),
        ),
      );
      expect(find.text('PLN (Pascabayar)'), findsOneWidget);
      expect(find.text('No. Meteran'), findsOneWidget);
      expect(find.text('187654321'), findsOneWidget);
      expect(find.text('Nominal Tagihan'), findsOneWidget);
      expect(find.text('Biaya Denda'), findsOneWidget);
      expect(find.text('Rp 2.500'), findsOneWidget);
      expect(find.text('Rp 56.000'), findsNWidgets(2));
    });

    testWidgets('billing receipt shows PPOB details with PLN Kode Token',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ReceiptPaper(transaction: buildBilling())),
      );
      expect(find.text('PAYMENT POINT'), findsNothing);
      expect(find.text('Jenis'), findsOneWidget);
      expect(find.text('PLN'), findsOneWidget);
      expect(find.text('Kode Token'), findsOneWidget);
      expect(find.text('123456789012'), findsOneWidget);
      expect(find.text('Nominal Tagihan'), findsOneWidget);
      expect(find.text('Admin Tambahan'), findsOneWidget);
      // Grand Total and the (non-cash) Total Bayar line both show the same value.
      expect(find.text('Rp 53.500'), findsNWidgets(2));
      expect(find.text('Total Bayar'), findsOneWidget);
    });
  });

  group('ReceiptPaper', () {
    Transaction buildTx({String method = 'cash', double discount = 0}) {
      final double discountApplied = discount > 0 ? discount : 0;
      return Transaction(
        id: 7,
        datetime: DateTime(2026, 9, 3, 9, 30),
        items: [
          TransactionItem(
            productId: 1,
            productName: 'Pakan Ayam 1kg',
            quantity: 2,
            price: 15000,
          ),
        ],
        subtotal: 30000,
        adminFee: 1000,
        discount: discountApplied,
        discountLabel: discountApplied > 0 ? 'Diskon 10%' : null,
        total: 31000 - discountApplied,
        cashReceived: 50000,
        change: 50000 - (31000 - discountApplied),
        buyerName: 'Budi',
        paymentMethod: method,
        paymentDetail: null,
      );
    }

    testWidgets('cash receipt shows Tunai Bayar and Kembalian',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: ReceiptPaper(transaction: buildTx())),
      );
      expect(find.text('No. Bill'), findsOneWidget);
      expect(find.text('Tunai Bayar'), findsOneWidget);
      expect(find.text('Kembalian'), findsOneWidget);
      expect(find.text('Biaya Admin'), findsOneWidget);
      expect(find.textContaining('TERIMA KASIH'), findsOneWidget);
    });

    testWidgets('non-cash receipt hides Tunai/Kembalian but shows Total Bayar',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReceiptPaper(
            transaction: buildTx(method: 'qris'),
          ),
        ),
      );
      expect(find.text('Tunai Bayar'), findsNothing);
      expect(find.text('Kembalian'), findsNothing);
      expect(find.text('Total Bayar'), findsOneWidget);
      expect(find.textContaining('QRIS'), findsWidgets);
    });

    testWidgets('receipt shows discount line when discount applied',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReceiptPaper(transaction: buildTx(discount: 3000)),
        ),
      );
      expect(find.text('Diskon 10%'), findsOneWidget);
      expect(find.text('- Rp 3.000'), findsOneWidget);
    });

    testWidgets('receipt hides discount line when no discount',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ReceiptPaper(transaction: buildTx()),
        ),
      );
      expect(find.text('- Rp 3.000'), findsNothing);
      expect(find.text('Diskon 10%'), findsNothing);
    });
  });
}