import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/database_helper.dart';
import '../models/admin_fee.dart';
import '../services/app_bus.dart';
import '../utils/format.dart';

class AdminFeeScreen extends StatefulWidget {
  const AdminFeeScreen({super.key});

  @override
  State<AdminFeeScreen> createState() => _AdminFeeScreenState();
}

class _AdminFeeScreenState extends State<AdminFeeScreen> {
  List<AdminFee> _fees = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final fees = await DatabaseHelper.instance.getAdminFees();
    if (mounted) {
      setState(() {
        _fees = fees;
        _loading = false;
      });
      AppBus.instance.notifyChanged();
    }
  }

  Future<void> _openForm({AdminFee? fee}) async {
    await showDialog(
      context: context,
      builder: (_) => _AdminFeeFormDialog(fee: fee, onSave: _load),
    );
  }

  Future<void> _confirmDelete(AdminFee fee) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Biaya Admin'),
        content: Text('Hapus "${fee.name}"? Transaksi lama tidak terpengaruh.'),
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
      await DatabaseHelper.instance.deleteAdminFee(fee.id!);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Atur Biaya Admin'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Tambah Biaya Admin',
            onPressed: () => _openForm(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Tambah'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _fees.isEmpty
              ? const Center(
                  child: Text('Belum ada biaya admin.\nTambahkan untuk memulai.',
                      textAlign: TextAlign.center),
                )
              : ReorderableListView(
                  onReorderItem: (oldIndex, newIndex) {
                    setState(() {
                      final item = _fees.removeAt(oldIndex);
                      _fees.insert(newIndex, item);
                    });
                    for (var i = 0; i < _fees.length; i++) {
                      DatabaseHelper.instance
                          .updateAdminFeeOrder(_fees[i].id!, i);
                    }
                    AppBus.instance.notifyChanged();
                  },
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    for (var i = 0; i < _fees.length; i++)
                      Card(
                        key: ValueKey(_fees[i].id),
                        margin: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        child: ListTile(
                          title: Text(_fees[i].name),
                          subtitle: Text(
                            formatRupiah(_fees[i].amount),
                            style: TextStyle(
                              fontWeight:
                                  _fees[i].amount > 0 ? FontWeight.w600 : null,
                              color: _fees[i].amount > 0
                                  ? Colors.teal
                                  : Colors.grey,
                            ),
                          ),
                          leading: ReorderableDragStartListener(
                            index: i,
                            child: const Icon(Icons.drag_handle),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Edit',
                                onPressed: () => _openForm(fee: _fees[i]),
                              ),
                              IconButton(
                                icon:
                                    const Icon(Icons.delete_outline,
                                        color: Colors.red),
                                tooltip: 'Hapus',
                                onPressed: () => _confirmDelete(_fees[i]),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _AdminFeeFormDialog extends StatefulWidget {
  final AdminFee? fee;
  final VoidCallback onSave;

  const _AdminFeeFormDialog({this.fee, required this.onSave});

  @override
  State<_AdminFeeFormDialog> createState() => _AdminFeeFormDialogState();
}

class _AdminFeeFormDialogState extends State<_AdminFeeFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _amountController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final fee = widget.fee;
    _nameController = TextEditingController(text: fee?.name ?? '');
    _amountController =
        TextEditingController(text: (fee?.amount ?? 0).toInt().toString());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final fee = AdminFee(
      id: widget.fee?.id,
      name: _nameController.text.trim(),
      amount: double.parse(_amountController.text),
      orderIndex: widget.fee?.orderIndex ?? 0,
    );

    if (widget.fee == null) {
      await DatabaseHelper.instance.insertAdminFee(fee);
    } else {
      await DatabaseHelper.instance.updateAdminFee(fee);
    }

    if (mounted) {
      Navigator.pop(context);
      widget.onSave();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.fee != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Biaya Admin' : 'Tambah Biaya Admin'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nama',
                hintText: 'Misal: Admin QRIS',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Nama wajib diisi';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Nominal',
                prefixText: 'Rp ',
                hintText: '0',
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Nominal wajib diisi';
                if (double.tryParse(v) == null) return 'Nominal tidak valid';
                return null;
              },
            ),
          ],
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
                  height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Simpan'),
        ),
      ],
    );
  }
}