import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/transaction.dart';
import '../services/app_bus.dart';
import '../utils/format.dart';
import 'receipt_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Transaction> _transactions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
    // Refresh automatically when a new sale is recorded so the newest item
    // appears without pulling to refresh.
    AppBus.instance.addListener(_loadTransactions);
  }

  @override
  void dispose() {
    AppBus.instance.removeListener(_loadTransactions);
    super.dispose();
  }

  Future<void> _loadTransactions() async {
    setState(() => _loading = true);
    final transactions =
        await DatabaseHelper.instance.getTransactions();
    if (mounted) {
      setState(() {
        _transactions = transactions;
        _loading = false;
      });
    }
  }

  void _showDetail(Transaction t) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReceiptScreen(
          transaction: t,
          appBarTitle: 'Detail Transaksi #${t.id}',
          doneLabel: 'Tutup',
        ),
      ),
    );
  }

  Future<void> _confirmDelete(Transaction t) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Riwayat'),
        content: Text('Hapus transaksi #${t.id} dari riwayat?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseHelper.instance.deleteTransaction(t.id!);
      _loadTransactions();
      AppBus.instance.notifyChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Transaksi'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _transactions.isEmpty
              ? const Center(
                  child: Text('Belum ada transaksi.',
                      style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                    padding: const EdgeInsets.all(8),
                    itemCount: _transactions.length,
                    itemBuilder: (context, index) {
                      final t = _transactions[index];
                      final itemCount = t.items
                          .fold(0, (sum, item) => sum + item.quantity);
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          onTap: () => _showDetail(t),
                          leading: const CircleAvatar(
                            child: Icon(Icons.receipt_long),
                          ),
                          title: Text(
                            '#${t.id}  ${formatDateTime(t.datetime)}',
                            style: const TextStyle(fontSize: 14),
                          ),
                          subtitle: Text(
                            '${paymentMethodByKey(t.paymentMethod).label} · $itemCount item(s) · ${formatRupiah(t.total)}',
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            onPressed: () => _confirmDelete(t),
                          ),
                          isThreeLine: true,
                          dense: true,
                        ),
                      );
                    },
                  ),
    );
  }
}