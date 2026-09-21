import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/database_helper.dart';
import '../models/admin_fee.dart';
import '../models/transaction.dart';
import '../services/app_bus.dart';
import '../services/app_settings.dart';
import '../utils/format.dart';
import '../widgets/cash_input_pad.dart';
import '../widgets/pin_entry_dialog.dart';
import 'receipt_screen.dart';

/// Payment Point (PPOB) service category definition used by [PaymentPointScreen].
class _BillCategory {
  final String name;
  final String referenceLabel;
  final IconData icon;
  final Color color;

  const _BillCategory({
    required this.name,
    required this.referenceLabel,
    required this.icon,
    required this.color,
  });
}

const _billCategories = <_BillCategory>[
  _BillCategory(
    name: 'PLN',
    referenceLabel: 'Kode Token',
    icon: Icons.bolt,
    color: Colors.teal,
  ),
  _BillCategory(
    name: 'PDAM',
    referenceLabel: 'No. Pelanggan',
    icon: Icons.water_drop,
    color: Colors.blue,
  ),
  _BillCategory(
    name: 'BPJS',
    referenceLabel: 'No. Peserta',
    icon: Icons.health_and_safety,
    color: Colors.orange,
  ),
];

/// Payment Point / PPOB: accepts tagihan PLN, PDAM and BPJS payments.
///
/// The form collects the bill reference (token / meter number for PLN),
/// the bill nominal, a standard admin fee from master data, and an optional
/// additional admin charge. The total (Nominal + Biaya Admin + Admin
/// Tambahan) is computed live. Completing a payment opens the same receipt
/// flow used by the POS, so the struk preview and thermal print are always
/// identical for sales and payment point.
class PaymentPointScreen extends StatefulWidget {
  const PaymentPointScreen({super.key});

  @override
  State<PaymentPointScreen> createState() => _PaymentPointScreenState();
}

class _PaymentPointScreenState extends State<PaymentPointScreen> {
  final _formKey = GlobalKey<FormState>();
  final _referenceCtrl = TextEditingController();
  final _nominalCtrl = TextEditingController();
  final _extraAdminCtrl = TextEditingController();
  final _fineCtrl = TextEditingController();
  final _customerNameCtrl = TextEditingController();

  String _category = 'PLN';
  String _plnMode = 'token';
  List<AdminFee> _adminFees = [];
  int? _selectedAdminFeeId;
  bool _loading = true;

  _BillCategory get _selectedCategory => _billCategories.firstWhere(
        (c) => c.name == _category,
        orElse: () => _billCategories.first,
      );

  AdminFee? get _selectedFee {
    for (final fee in _adminFees) {
      if (fee.id == _selectedAdminFeeId) return fee;
    }
    return null;
  }

  double get _nominal => double.tryParse(_nominalCtrl.text) ?? 0;
  double get _adminFee => _selectedFee?.amount ?? 0;
  double get _extraAdmin => double.tryParse(_extraAdminCtrl.text) ?? 0;

  /// Biaya Denda (late-payment fine) — only charged on PLN pascabayar.
  double get _fine => double.tryParse(_fineCtrl.text) ?? 0;

  double get _total => _nominal + _adminFee + _extraAdmin + _fine;

  /// Label for the bill-reference input; PLN switches between the token
  /// (prabayar) and the meter number (pascabayar).
  String get _referenceLabel {
    if (_category != 'PLN') return _selectedCategory.referenceLabel;
    return _plnMode == 'pascabayar' ? 'No. Meteran' : 'Kode Token';
  }

  /// Label for the main bill input; pascabayar reads "Pemakaian / Tagihan
  /// Utama", everything else "Nominal Tagihan".
  String get _nominalLabel =>
      _category == 'PLN' && _plnMode == 'pascabayar'
          ? 'Pemakaian / Tagihan Utama'
          : 'Nominal Tagihan';

  @override
  void initState() {
    super.initState();
    _loadAdminFees();
    AppBus.instance.addListener(_loadAdminFees);
  }

  @override
  void dispose() {
    AppBus.instance.removeListener(_loadAdminFees);
    _referenceCtrl.dispose();
    _nominalCtrl.dispose();
    _extraAdminCtrl.dispose();
    _fineCtrl.dispose();
    _customerNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAdminFees() async {
    final fees = await DatabaseHelper.instance.getAdminFees();
    if (!mounted) return;
    setState(() {
      _adminFees = fees;
      // Keep a valid selection: default to the first fee (Tanpa Admin if
      // present) whenever nothing matched or the old one is gone.
      if (_selectedAdminFeeId == null ||
          !fees.any((f) => f.id == _selectedAdminFeeId)) {
        _selectedAdminFeeId = fees.isNotEmpty ? fees.first.id : null;
      }
      _loading = false;
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _resetForm() {
    setState(() {
      _referenceCtrl.clear();
      _nominalCtrl.clear();
      _extraAdminCtrl.clear();
      _fineCtrl.clear();
      _customerNameCtrl.clear();
      _plnMode = 'token';
      if (_adminFees.isNotEmpty) {
        _selectedAdminFeeId = _adminFees.first.id;
      }
    });
  }

  // ---------------- Checkout ----------------
  Future<void> _checkout() async {
    if (!_formKey.currentState!.validate()) return;

    // Same cashier PIN gate used by the POS "Bayar" button (if configured).
    if (AppSettings.instance.hasPin) {
      final verified = await promptPin(
        context,
        verify: (pin) => AppSettings.instance.verifyPin(pin),
      );
      if (!verified) return;
    }

    final details = await _showPaymentDialog();
    if (details == null) return;

    final isCash = details.method.key == 'cash';
    double change = 0;
    if (isCash) {
      if (details.cashAmount < _total) {
        _showSnack('Uang tunai kurang dari total tagihan.');
        return;
      }
      change = details.cashAmount - _total;
    }

    final category = _selectedCategory;
    final reference = _referenceCtrl.text.trim();
    final customerName = _customerNameCtrl.text.trim().isEmpty
        ? null
        : _customerNameCtrl.text.trim();

    final transaction = Transaction(
      datetime: DateTime.now(),
      billNumber: generateBillNumber(),
      items: [
        // The bill nominal is a pass-through to the provider, so the synthetic
        // line carries cost = nominal: no profit is (wrongly) attributed to
        // the bill itself, while admin fees still show as revenue.
        TransactionItem(
          productId: 0,
          productName: 'Tagihan ${category.name}',
          quantity: 1,
          price: _nominal,
          cost: _nominal,
        ),
      ],
      subtotal: _nominal,
      adminFee: _adminFee,
      adminFeeId: _selectedAdminFeeId,
      total: _total,
      cashReceived: isCash ? details.cashAmount : _total,
      change: change,
      buyerName: customerName,
      paymentMethod: details.method.key,
      paymentDetail: details.reference,
      type: 'billing',
      billingCategory: category.name,
      billingReference: reference,
      extraAdmin: _extraAdmin,
      billingSubcategory: _category == 'PLN' ? _plnMode : null,
      billingFine: _fine,
    );

    try {
      final newId =
          await DatabaseHelper.instance.insertTransaction(transaction);

      if (!mounted) return;

      final savedTransaction = Transaction(
        id: newId,
        datetime: transaction.datetime,
        billNumber: transaction.billNumber,
        items: transaction.items,
        subtotal: transaction.subtotal,
        adminFee: transaction.adminFee,
        adminFeeId: transaction.adminFeeId,
        total: transaction.total,
        cashReceived: transaction.cashReceived,
        change: transaction.change,
        buyerName: transaction.buyerName,
        paymentMethod: transaction.paymentMethod,
        paymentDetail: transaction.paymentDetail,
        type: transaction.type,
        billingCategory: transaction.billingCategory,
        billingReference: transaction.billingReference,
        extraAdmin: transaction.extraAdmin,
        billingSubcategory: transaction.billingSubcategory,
        billingFine: transaction.billingFine,
      );

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReceiptScreen(
            transaction: savedTransaction,
            appBarTitle: 'Struk Payment Point',
            doneLabel: 'Selesai',
          ),
        ),
      );
      if (!mounted) return;
      _resetForm();
      AppBus.instance.notifyChanged();
    } catch (e) {
      debugPrint('Gagal menyimpan pembayaran Payment Point: $e');
      _showSnack('Gagal menyimpan pembayaran. Coba lagi.');
    }
  }

  /// Compact payment dialog: method chips (Tunai / QRIS / E-Wallet / Transfer),
  /// a cash amount pad for Tunai, and an optional reference number.
  Future<_PPaymentDetails?> _showPaymentDialog() {
    return showDialog<_PPaymentDetails>(
      context: context,
      builder: (context) {
        String selectedMethod = 'cash';
        String cashText = '';
        final referenceCtrl = TextEditingController();

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Pembayaran Tagihan'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total: ${formatRupiah(_total)}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final method in paymentMethods)
                        ChoiceChip(
                          avatar: Icon(method.icon, size: 18),
                          label: Text(method.label),
                          selected: selectedMethod == method.key,
                          onSelected: (_) {
                            setDialogState(
                                () => selectedMethod = method.key);
                          },
                        ),
                    ],
                  ),
                  if (selectedMethod == 'cash') ...[
                    const SizedBox(height: 4),
                    CashInputPad(
                      total: _total,
                      amount: cashText,
                      onChanged: (v) =>
                          setDialogState(() => cashText = v),
                    ),
                  ] else ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: referenceCtrl,
                      keyboardType: TextInputType.text,
                      decoration: const InputDecoration(
                        labelText: 'No. Referensi (opsional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () {
                  if (selectedMethod == 'cash') {
                    final v = int.tryParse(cashText);
                    if (v == null) {
                      _showSnack('Masukkan jumlah uang tunai.');
                      return;
                    }
                    if (v < _total) {
                      _showSnack('Uang tunai kurang dari total tagihan.');
                      return;
                    }
                  }
                  Navigator.pop(
                    context,
                    _PPaymentDetails(
                      method: paymentMethodByKey(selectedMethod),
                      cashAmount: selectedMethod == 'cash'
                          ? double.parse(cashText)
                          : _total,
                      reference: referenceCtrl.text.trim().isEmpty
                          ? null
                          : referenceCtrl.text.trim(),
                    ),
                  );
                },
                child: const Text('Bayar'),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------- Build ----------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Payment Point')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _sectionHeader('Jenis Tagihan', Icons.category_outlined),
                  const SizedBox(height: 8),
                  _buildCategorySelector(),
                  if (_category == 'PLN') ...[
                    const SizedBox(height: 16),
                    _buildPlnTypeSelector(),
                  ],
                  const SizedBox(height: 20),
                  _sectionHeader('Detail Tagihan', Icons.description_outlined),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _referenceCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(30),
                    ],
                    decoration: InputDecoration(
                      labelText: _referenceLabel,
                      prefixIcon: Icon(_selectedCategory.icon),
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return '$_referenceLabel wajib diisi';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nominalCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(12),
                    ],
                    decoration: InputDecoration(
                      labelText: _nominalLabel,
                      prefixText: 'Rp ',
                      border: const OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final value = double.tryParse(v ?? '');
                      if (value == null || value <= 0) {
                        return 'Masukkan nominal tagihan';
                      }
                      return null;
                    },
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_category == 'PLN' && _plnMode == 'pascabayar') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _fineCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(12),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Biaya Denda Tagihan (opsional)',
                        prefixText: 'Rp ',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _customerNameCtrl,
                    keyboardType: TextInputType.text,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nama Pelanggan (opsional)',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionHeader('Biaya & Total', Icons.calculate_outlined),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int>(
                    initialValue: _selectedAdminFeeId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Biaya Admin',
                      border: OutlineInputBorder(),
                    ),
                    items: _adminFees.map((f) {
                      return DropdownMenuItem(
                        value: f.id,
                        child: Text(
                          f.amount > 0
                              ? '${f.name} (+${formatRupiah(f.amount)})'
                              : f.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: _adminFees.isEmpty
                        ? null
                        : (id) {
                            setState(() => _selectedAdminFeeId = id);
                          },
                  ),
                  if (_adminFees.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Belum ada biaya admin. Atur lewat menu pengaturan.',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _extraAdminCtrl,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(12),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Admin Tambahan (opsional)',
                      prefixText: 'Rp ',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 16),
                  _buildSummaryCard(),
                  const SizedBox(height: 20),
                  SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _total > 0 ? _checkout : null,
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Bayar',
                          style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildCategorySelector() {
    return Row(
      children: [
        for (final category in _billCategories) ...[
          Expanded(
            child: _categoryCard(category),
          ),
          if (category != _billCategories.last) const SizedBox(width: 10),
        ],
      ],
    );
  }

  /// PLN sub-kind picker: Token Listrik (Prabayar) vs Bayar Listrik
  /// (Pascabayar). Only shown when the PLN category is selected.
  Widget _buildPlnTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Jenis Transaksi PLN',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Token Listrik (Prabayar)'),
              selected: _plnMode == 'token',
              onSelected: (_) => setState(() => _plnMode = 'token'),
            ),
            ChoiceChip(
              label: const Text('Bayar Listrik (Pascabayar)'),
              selected: _plnMode == 'pascabayar',
              onSelected: (_) => setState(() => _plnMode = 'pascabayar'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _categoryCard(_BillCategory category) {
    final selected = _category == category.name;
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: selected
            ? category.color.withValues(alpha: 0.12)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? category.color : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _category = category.name),
        child: Column(
          children: [
            Icon(category.icon,
                size: 32,
                color: selected ? category.color : scheme.onSurfaceVariant),
            const SizedBox(height: 8),
            Text(
              category.name,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: selected
                    ? category.color
                    : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _summaryRow('Nominal Tagihan', formatRupiah(_nominal)),
            const SizedBox(height: 4),
            _summaryRow('Biaya Admin', formatRupiah(_adminFee)),
            const SizedBox(height: 4),
            _summaryRow(
              'Admin Tambahan',
              _extraAdmin > 0 ? formatRupiah(_extraAdmin) : '-',
            ),
            if (_fine > 0) ...[
              const SizedBox(height: 4),
              _summaryRow('Biaya Denda', formatRupiah(_fine)),
            ],
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total',
                    style: Theme.of(context).textTheme.titleLarge),
                Text(
                  formatRupiah(_total),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: scheme.primary, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        Text(value,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _PPaymentDetails {
  final PaymentMethod method;
  final double cashAmount;
  final String? reference;

  _PPaymentDetails({
    required this.method,
    required this.cashAmount,
    this.reference,
  });
}