import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/transaction.dart';
import '../services/app_bus.dart';
import '../utils/format.dart';
import 'expense_screen.dart';
import 'report_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Transaction> _transactions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    // Refresh automatically whenever a transaction/product changes anywhere
    // (e.g. a new sale completes), so stats stay live without manual refresh.
    AppBus.instance.addListener(_load);
  }

  @override
  void dispose() {
    AppBus.instance.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final tx = await DatabaseHelper.instance.getTransactions();
    if (mounted) {
      setState(() {
        _transactions = tx;
        _loading = false;
      });
    }
  }

  double get _grossRevenue =>
      _transactions.fold(0, (sum, t) => sum + t.total);

  double get _revenueToday {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return _transactions
        .where((t) => !t.datetime.isBefore(start))
        .fold(0.0, (sum, t) => sum + t.total);
  }

  int get _transactionCountToday {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    return _transactions.where((t) => !t.datetime.isBefore(start)).length;
  }

  int get _transactionCount => _transactions.length;

  List<MapEntry<String, int>> get _bestProducts {
    final counts = <String, int>{};
    for (final t in _transactions) {
      // Skip Payment Point transactions: their synthetic "Tagihan ..." line
      // is not a real product and would pollute the best-seller ranking.
      if (t.isBilling) continue;
      for (final item in t.items) {
        counts[item.productName] = (counts[item.productName] ?? 0) + item.quantity;
      }
    }
    final list = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list.take(5).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Laporan & Tutup Kasir',
            icon: const Icon(Icons.insert_chart_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ReportScreen()),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 640;
                final statCards = _statCardData();
                return ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                              child: _MenuCard(
                            icon: Icons.insert_chart_outlined,
                            title: 'Laporan & Tutup Kasir',
                            subtitle: 'Rekap harian & bulanan',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ReportScreen()),
                            ),
                          )),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _MenuCard(
                            icon: Icons.payments_outlined,
                            title: 'Pengeluaran Toko',
                            subtitle: 'Catat biaya operasional',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => const ExpenseScreen()),
                            ),
                          )),
                        ],
                      )
                    else ...[
                      _MenuCard(
                        icon: Icons.insert_chart_outlined,
                        title: 'Laporan & Tutup Kasir',
                        subtitle: 'Rekap harian & bulanan',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ReportScreen()),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _MenuCard(
                        icon: Icons.payments_outlined,
                        title: 'Pengeluaran Toko',
                        subtitle: 'Catat biaya operasional',
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ExpenseScreen()),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: isWide ? 2 : 1,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: isWide ? 2.6 : 3.0,
                      ),
                      itemCount: statCards.length,
                      itemBuilder: (context, index) {
                        final c = statCards[index];
                        return _StatCard(
                          label: c.label,
                          value: c.value,
                          icon: c.icon,
                          color: c.color,
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Produk Terlaris',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: _bestProducts.isEmpty
                            ? const Text('Belum ada penjualan.',
                                style: TextStyle(color: Colors.grey))
                            : Column(
                                children: [
                                  for (final entry in _bestProducts)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 6),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              entry.key,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Text(
                                            '${entry.value} terjual',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: Colors.green,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  List<_StatCardData> _statCardData() {
    return [
      _StatCardData(
        'Pendapatan Hari Ini', formatRupiah(_revenueToday),
        Icons.today, Colors.green),
      _StatCardData(
        'Total Penjualan', formatRupiah(_grossRevenue),
        Icons.monetization_on, Colors.blue),
      _StatCardData(
        'Transaksi Hari Ini', '$_transactionCountToday',
        Icons.receipt_long, Colors.orange),
      _StatCardData(
        'Total Transaksi', '$_transactionCount',
        Icons.assessment, Colors.purple),
    ];
  }
}

class _StatCardData {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCardData(this.label, this.value, this.icon, this.color);
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}