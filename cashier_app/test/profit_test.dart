import 'package:flutter_test/flutter_test.dart';

import 'package:cashier_app/models/expense.dart';
import 'package:cashier_app/models/transaction.dart';
import 'package:cashier_app/utils/profit.dart';

void main() {
  Transaction tx(double sell, double cost, int qty, {double admin = 0}) {
    final subtotal = sell * qty;
    return Transaction(
      id: 1,
      datetime: DateTime(2026, 9, 6, 10, 0),
      items: [
        TransactionItem(
          productId: 1,
          productName: 'Barang',
          quantity: qty,
          price: sell,
          cost: cost,
        ),
      ],
      subtotal: subtotal,
      adminFee: admin,
      total: subtotal + admin,
      cashReceived: subtotal + admin,
      change: 0,
      paymentMethod: 'cash',
    );
  }

  group('TransactionItem.profit', () {
    test('selisih harga jual dan modal kali qty', () {
      final item = TransactionItem(
        productId: 1,
        productName: 'x',
        quantity: 3,
        price: 15000,
        cost: 10000,
      );
      expect(item.profit, 15000);
    });

    test('preserves cost across toMap/fromMap, defaults to 0 for legacy', () {
      final item = TransactionItem(
        productId: 1,
        productName: 'x',
        quantity: 2,
        price: 50000,
        cost: 40000,
      );
      expect(TransactionItem.fromMap(item.toMap()).cost, 40000);
      expect(
        TransactionItem.fromMap(
          {'product_id': 1, 'product_name': 'x', 'quantity': 1, 'price': 5},
        ).cost,
        0,
      );
    });
  });

  group('ProfitCalculator', () {
    test('cogs menjumlahkan modal per item', () {
      final txns = [tx(15000, 10000, 2), tx(20000, 15000, 3)];
      expect(ProfitCalculator.cogsOf(txns), 65000);
    });

    test('laba kotor = pendapatan - hpp', () {
      final txns = [tx(15000, 10000, 2), tx(20000, 15000, 3)];
      final summary = ProfitCalculator.summarize(
        transactions: txns,
        expenses: const [],
      );
      expect(summary.revenue, 90000);
      expect(summary.grossProfit, 25000);
      expect(summary.netProfit, 25000);
    });

    test('laba bersih dikurangi pengeluaran operasional', () {
      final txns = [tx(15000, 10000, 2, admin: 1000)];
      final summary = ProfitCalculator.summarize(
        transactions: txns,
        expenses: [
          Expense(id: 1, datetime: DateTime(2026, 9, 6), amount: 8000, note: ''),
        ],
      );
      // revenue 31.000 - hpp 20.000 = laba kotor 11.000 - pengeluaran 8.000
      expect(summary.grossProfit, 11000);
      expect(summary.netProfit, 3000);
    });

    test('hasil negatif berarti rugi', () {
      final txns = [tx(15000, 15000, 1, admin: 1000)];
      final summary = ProfitCalculator.summarize(
        transactions: txns,
        expenses: [
          Expense(id: 1, datetime: DateTime(2026, 9, 6), amount: 5000, note: ''),
        ],
      );
      expect(summary.netProfit, -4000);
    });
  });
}