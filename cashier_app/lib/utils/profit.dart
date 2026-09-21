import '../models/expense.dart';
import '../models/transaction.dart';

/// Monthly / daily profit & loss summary derived from sales and expenses.
///
///  - [revenue]: total money received (transaction totals, incl. admin fee and
///    after discount).
///  - [cogs]:  harga pokok penjualan — the sum of (cost price x quantity) of
///    every item sold.
///  - [expenses]: operational store expenses (pengeluaran).
class ProfitSummary {
  final double revenue;
  final double cogs;
  final double expenses;

  const ProfitSummary({
    required this.revenue,
    required this.cogs,
    required this.expenses,
  });

  /// Laba kotor = pendapatan - modal barang.
  double get grossProfit => revenue - cogs;

  /// Laba bersih = laba kotor - pengeluaran operasional (negatif = rugi).
  double get netProfit => grossProfit - expenses;
}

abstract final class ProfitCalculator {
  /// Sum of (cost x quantity) across all items sold in [transactions].
  static double cogsOf(List<Transaction> transactions) {
    var total = 0.0;
    for (final t in transactions) {
      for (final item in t.items) {
        total += item.cost * item.quantity;
      }
    }
    return total;
  }

  static ProfitSummary summarize({
    required List<Transaction> transactions,
    required List<Expense> expenses,
  }) {
    final revenue =
        transactions.fold(0.0, (sum, t) => sum + t.total);
    final expTotal = expenses.fold(0.0, (sum, e) => sum + e.amount);
    return ProfitSummary(
      revenue: revenue,
      cogs: cogsOf(transactions),
      expenses: expTotal,
    );
  }
}