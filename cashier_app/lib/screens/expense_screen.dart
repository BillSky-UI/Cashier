import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/database_helper.dart';
import '../models/expense.dart';
import '../services/app_bus.dart';
import '../utils/format.dart';

/// Screen to record and manage operational store expenses (outside of sales),
/// e.g. electricity, plastic bags. Kept locally so reports can show accurate
/// profit (revenue - expenses).
class ExpenseScreen extends StatefulWidget {
  const ExpenseScreen({super.key});

  @override
  State<ExpenseScreen> createState() => _ExpenseScreenState();
}

class _ExpenseScreenState extends State<ExpenseScreen> {
  List<Expense> _expenses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final expenses = await DatabaseHelper.instance.getExpenses();
    if (mounted) {
      setState(() {
        _expenses = expenses;
        _loading = false;
      });
      AppBus.instance.notifyChanged();
    }
  }

  double get _total =>
      _expenses.fold(0.0, (sum, e) => sum + e.amount);

  double get _thisMonthTotal {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 1);
    return _expenses
        .where((e) =>
            !e.datetime.isBefore(start) && e.datetime.isBefore(end))
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  Future<void> _openForm({Expense? expense}) async {
    await showDialog(
      context: context,
      builder: (_) => _ExpenseFormDialog(expense: expense, onSave: _load),
    );
  }

  Future<void> _confirmDelete(Expense expense) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Pengeluaran'),
        content: Text(
            'Hapus pengeluaran "${expense.note.isEmpty ? 'Tanpa keterangan' : expense.note}" senilai ${formatRupiah(expense.amount)}?'),
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
      await DatabaseHelper.instance.deleteExpense(expense.id!);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengeluaran Toko'),
        actions: [
          IconButton(
            tooltip: 'Tambah Pengeluaran',
            icon: const Icon(Icons.add),
            onPressed: () => _openForm(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Catat'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: _StatBox(
                          label: 'Total Pengeluaran',
                          value: formatRupiah(_total),
                          color: scheme.error,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _StatBox(
                          label: 'Bulan Ini',
                          value: formatRupiah(_thisMonthTotal),
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: _expenses.isEmpty
                      ? const Center(
                          child: Text(
                            'Belum ada pengeluaran.\nCatat pengeluaran toko di sini.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 88),
                          itemCount: _expenses.length,
                          itemBuilder: (context, index) {
                            final e = _expenses[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 4),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: scheme.errorContainer,
                                  child: Icon(Icons.receipt_outlined,
                                      color: scheme.onErrorContainer),
                                ),
                                title: Text(
                                  e.note.isEmpty ? 'Tanpa keterangan' : e.note,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(formatDateTime(e.datetime)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      formatRupiah(e.amount),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.red),
                                      tooltip: 'Hapus',
                                      onPressed: () => _confirmDelete(e),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatBox({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpenseFormDialog extends StatefulWidget {
  final Expense? expense;
  final VoidCallback onSave;

  const _ExpenseFormDialog({this.expense, required this.onSave});

  @override
  State<_ExpenseFormDialog> createState() => _ExpenseFormDialogState();
}

class _ExpenseFormDialogState extends State<_ExpenseFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amountController;
  late final TextEditingController _noteController;
  late DateTime _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.expense;
    _amountController =
        TextEditingController(text: (e?.amount ?? 0).toInt().toString());
    _noteController = TextEditingController(text: e?.note ?? '');
    _date = e?.datetime ?? DateTime.now();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _date = DateTime(
            picked.year, picked.month, picked.day, _date.hour, _date.minute);
      });
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final expense = Expense(
      id: widget.expense?.id,
      datetime: _date,
      amount: double.parse(_amountController.text),
      note: _noteController.text.trim(),
    );
    await DatabaseHelper.instance.insertExpense(expense);
    if (mounted) {
      Navigator.pop(context);
      widget.onSave();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.expense != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Pengeluaran' : 'Catat Pengeluaran'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(formatDateTime(_date)),
                subtitle: const Text('Tanggal'),
                onTap: _pickDate,
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Nominal (Rp)',
                  prefixText: 'Rp ',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Nominal wajib diisi';
                  final value = double.tryParse(v);
                  if (value == null || value <= 0) return 'Nominal tidak valid';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Keterangan',
                  hintText: 'Misal: Biaya listrik, beli kantong plastik',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Simpan'),
        ),
      ],
    );
  }
}
