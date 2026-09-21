import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/database_helper.dart';
import '../models/category.dart';
import '../models/admin_fee.dart';
import '../models/product.dart';
import '../models/transaction.dart';
import '../services/app_bus.dart';
import '../services/app_settings.dart';
import '../utils/format.dart';
import '../widgets/cash_input_pad.dart';
import '../widgets/live_clock.dart';
import '../widgets/pin_entry_dialog.dart';
import '../widgets/product_grid_card.dart';
import 'receipt_screen.dart';

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen> {
  final _searchController = TextEditingController();
  List<Product> _products = [];
  List<AdminFee> _adminFees = [];
  int? _selectedAdminFeeId;
  final List<_CartItem> _cart = [];
  bool _loading = true;

  // Active discount / voucher. Only one of {percent, rupiah} is used at a time.
  double? _discountPercent;
  double? _discountRupiah;

  // Products grouped by category (maintained by _loadData). Products without a
  // category are collected into a pseudo "Tanpa Kategori" group.
  List<Category> _categories = [];
  Map<int, List<Product>> _productsByCategory = {};
  List<Product> _uncategorized = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    AppBus.instance.addListener(_loadData);
  }

  @override
  void dispose() {
    AppBus.instance.removeListener(_loadData);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final products = await DatabaseHelper.instance
        .getProducts(searchQuery: _searchController.text);
    final categories = await DatabaseHelper.instance.getCategories();
    final fees = await DatabaseHelper.instance.getAdminFees();
    if (mounted) {
      setState(() {
        _products = products;
        _categories = categories;
        // Group products under their category id.
        final grouped = <int, List<Product>>{};
        final uncategorized = <Product>[];
        for (final p in products) {
          final catId = p.categoryId;
          if (catId != null) {
            grouped.putIfAbsent(catId, () => []).add(p);
          } else {
            uncategorized.add(p);
          }
        }
        _productsByCategory = grouped;
        _uncategorized = uncategorized;
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
  }

  AdminFee? get _selectedFee {
    for (final fee in _adminFees) {
      if (fee.id == _selectedAdminFeeId) return fee;
    }
    return null;
  }

  double get _adminFee => _selectedFee?.amount ?? 0;

  double get _subtotal =>
      _cart.fold(0.0, (sum, item) => sum + (item.product.price * item.quantity));

  /// Computed discount amount (rupiah) applied to [subtotal]. Never exceeds the
  /// subtotal. A rupiah value, if set, takes precedence over a percent value.
  double get _discount {
    final rupiah = _discountRupiah ?? 0;
    if (rupiah > 0) return rupiah.clamp(0, _subtotal);
    final pct = _discountPercent ?? 0;
    if (pct <= 0) return 0;
    return (_subtotal * pct / 100).clamp(0, _subtotal);
  }

  bool get _hasDiscount => _discount > 0;

  /// Human-readable discount description for the receipt / report.
  String? get _discountLabel {
    final rupiah = _discountRupiah ?? 0;
    if (rupiah > 0) return 'Voucher ${formatRupiah(rupiah)}';
    final pct = _discountPercent ?? 0;
    if (pct > 0) return 'Diskon ${pct.toStringAsFixed(pct.truncateToDouble() == pct ? 0 : 1)}%';
    return null;
  }

  double get _total => (_subtotal + _adminFee - _discount).clamp(0, double.infinity);

  int get _totalItems => _cart.fold(0, (sum, item) => sum + item.quantity);

  // ---------------- Cart mutation methods (single source of truth) ----------------
  // Every method calls `setState` so both the cart panel/sheet and totals
  // reflect changes immediately.

  void _addToCart(Product product) {
    if (product.stock <= 0) return;
    final index = _cart.indexWhere((c) => c.product.id == product.id);
    setState(() {
      if (index >= 0) {
        final existing = _cart[index];
        if (existing.quantity < product.stock) {
          _cart[index] = _CartItem(
            product: product,
            quantity: existing.quantity + 1,
          );
        } else {
          _showSnack('Stok ${product.name} tidak mencukupi.');
        }
      } else {
        _cart.add(_CartItem(product: product, quantity: 1));
      }
    });
  }

  void _decreaseCartItem(int index) {
    setState(() {
      final item = _cart[index];
      if (item.quantity <= 1) {
        _cart.removeAt(index);
      } else {
        _cart[index] = _CartItem(
          product: item.product,
          quantity: item.quantity - 1,
        );
      }
    });
  }

  void _increaseCartItem(Product product) {
    _addToCart(product);
  }

  void _removeAllFromCart(Product product) {
    setState(() {
      _cart.removeWhere((c) => c.product.id == product.id);
    });
  }

  void _clearCart() {
    setState(() {
      _cart.clear();
      _discountPercent = null;
      _discountRupiah = null;
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------------- Checkout ----------------
  Future<void> _checkout() async {
    if (_cart.isEmpty) {
      _showSnack('Keranjang masih kosong.');
      return;
    }

    for (final item in _cart) {
      if (item.product.stock < item.quantity) {
        _showSnack(
            'Stok ${item.product.name} hanya tersisa ${item.product.stock}.');
        return;
      }
    }

    // Security gate: the "Bayar" action only proceeds to the payment step when
    // the configured 4-digit PIN (set in Pengaturan) is entered correctly.
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
        _showSnack('Uang tunai kurang dari total belanja.');
        return;
      }
      change = details.cashAmount - _total;
    }

    final transaction = Transaction(
      datetime: DateTime.now(),
      billNumber: generateBillNumber(),
      items: _cart
          .map((c) => TransactionItem(
                productId: c.product.id!,
                productName: c.product.name,
                quantity: c.quantity,
                price: c.product.price,
                cost: c.product.costPrice,
              ))
          .toList(),
      subtotal: _subtotal,
      adminFee: _adminFee,
      discount: _discount,
      discountLabel: _discountLabel,
      adminFeeId: _selectedAdminFeeId,
      total: _total,
      cashReceived: isCash ? details.cashAmount : _total,
      change: change,
      buyerName: details.buyerName,
      paymentMethod: details.method.key,
      paymentDetail: details.paymentDetail,
    );

    // Persist FIRST. Only navigate to the receipt on success. The sheet must
    // remain open during the payment dialog, so never pop before checkout.
    try {
      final newId = await DatabaseHelper.instance.insertTransaction(transaction);

      for (final item in _cart) {
        await DatabaseHelper.instance
            .reduceStock(item.product.id!, item.quantity);
      }

      // Assign the real database id so the receipt can show the bill reference.
      final savedTransaction = Transaction(
        id: newId,
        datetime: transaction.datetime,
        billNumber: transaction.billNumber,
        items: transaction.items,
        subtotal: transaction.subtotal,
        adminFee: transaction.adminFee,
        discount: transaction.discount,
        discountLabel: transaction.discountLabel,
        adminFeeId: transaction.adminFeeId,
        total: transaction.total,
        cashReceived: transaction.cashReceived,
        change: transaction.change,
        buyerName: transaction.buyerName,
        paymentMethod: transaction.paymentMethod,
        paymentDetail: transaction.paymentDetail,
      );

      if (!mounted) return;

      // Close the cart sheet (portrait modal) before showing the receipt page.
      Navigator.of(context)
        ..popUntil((route) => route.isFirst)
        ..push(
          MaterialPageRoute(
            builder: (_) => ReceiptScreen(transaction: savedTransaction),
          ),
        ).then((_) {
          if (!mounted) return;
          setState(() {
            _cart.clear();
            _discountPercent = null;
            _discountRupiah = null;
            _selectedAdminFeeId = _adminFees.isNotEmpty ? _adminFees.first.id : null;
          });
          _loadData();
          // Notify every other screen (Dashboard, Riwayat, Produk) so they
          // refresh immediately without a manual pull-to-refresh.
          AppBus.instance.notifyChanged();
        });
    } catch (e, s) {
      debugPrint('KRITIS: Gagal menyimpan transaksi.');
      debugPrint('Exception: $e');
      debugPrint('Stack: $s');
      final message = e.toString();
      if (message.contains('no column named admin_fee_id')) {
        _showSnack('Skema DB belum sesuai versi. Klik ikon muat ulang lalu coba lagi.');
      } else if (message.contains('database is locked')) {
        _showSnack('Database sedang sibuk. Coba lagi.');
      } else {
        _showSnack('Gagal menyimpan transaksi. Coba lagi.');
      }
    }
  }

  Future<_PaymentDetails?> _showPaymentDialog() {
    return showDialog<_PaymentDetails>(
      context: context,
      builder: (context) {
        final buyerController = TextEditingController();
        final detailController = TextEditingController();
        final formKey = GlobalKey<FormState>();

        String selectedMethod = 'cash';
        String cashText = '';

        Widget cashField(void Function(VoidCallback fn) setDialogState) {
          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: CashInputPad(
              total: _total,
              amount: cashText,
              onChanged: (v) => setDialogState(() => cashText = v),
            ),
          );
        }

        Widget infoPanel(BuildContext dialogContext) {
          final scheme = Theme.of(dialogContext).colorScheme;

          Widget accountCard({
            required String title,
            required String number,
            required String owner,
            required Color accent,
          }) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: accent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: accent,
                    child: Text(
                      title.substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          number,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                        Text(
                          owner,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    tooltip: 'Salin nomor',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: number));
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text('Nomor $title disalin')),
                      );
                    },
                  ),
                ],
              ),
            );
          }

          Widget qrisPanel() {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'QRIS - Pembayaran Instan',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'logo/Qris.jpeg',
                      height: 190,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stack) => Container(
                        height: 190,
                        width: double.infinity,
                        alignment: Alignment.center,
                        child: Text(
                          'Gambar QRIS tidak ditemukan',
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.qr_code_scanner,
                        size: 18,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Minta pelanggan memindai QRIS di layar ini',
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (selectedMethod == 'qris')
                  qrisPanel()
                else if (selectedMethod == 'ewallet') ...[
                  accountCard(
                    title: 'Dana',
                    number: '0851-2604-5481',
                    owner: 'Setia Budi',
                    accent: scheme.primary,
                  ),
                  accountCard(
                    title: 'GoPay',
                    number: '0838-7885-1008',
                    owner: 'Nabil Al Kaysan',
                    accent: scheme.tertiary,
                  ),
                ] else
                  accountCard(
                    title: 'Seabank',
                    number: '9019-6065-12190',
                    owner: 'Nabil Al Kaysan',
                    accent: scheme.secondary,
                  ),
                TextFormField(
                  controller: detailController,
                  keyboardType: TextInputType.text,
                  decoration: const InputDecoration(
                    labelText: 'No. Referensi (opsional)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          );
        }

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Pembayaran'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total: ${formatRupiah(_total)}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: buyerController,
                      keyboardType: TextInputType.text,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nama Pembeli (opsional)',
                        prefixIcon: Icon(Icons.person_outline),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text('Metode Pembayaran',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
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
                    if (selectedMethod == 'cash') cashField(setDialogState),
                    if (selectedMethod != 'cash') infoPanel(context),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () {
                  if (!formKey.currentState!.validate()) return;
                  if (selectedMethod == 'cash') {
                    final v = int.tryParse(cashText);
                    if (v == null) {
                      _showSnack('Masukkan jumlah uang tunai.');
                      return;
                    }
                    if (v < _total) {
                      _showSnack('Uang tunai kurang dari total belanja.');
                      return;
                    }
                  }
                  Navigator.pop(
                    context,
                    _PaymentDetails(
                      method: paymentMethodByKey(selectedMethod),
                      buyerName: buyerController.text.trim().isEmpty
                          ? null
                          : buyerController.text.trim(),
                      cashAmount: selectedMethod == 'cash'
                          ? double.parse(cashText)
                          : _total,
                      paymentDetail: detailController.text.trim().isEmpty
                          ? null
                          : detailController.text.trim(),
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
      appBar: AppBar(
        title: const Text('Kasir'),
        actions: [
          if (_cart.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Kosongkan Keranjang',
              onPressed: _clearCart,
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Real-time weekday / date / time at the top-left of the page.
          const LiveClock(),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth >= 800;
                final productArea = _buildProductArea();

                if (isWide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: productArea),
                      SizedBox(width: 340, child: _buildCartPanel()),
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: productArea),
                    _buildBottomSummaryBar(context),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductArea() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => _loadData(),
            decoration: InputDecoration(
              hintText: 'Cari produk...',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _buildProductList(),
        ),
      ],
    );
  }

  /// Renders the product grid grouped by category. Categories are shown in
  /// their managed order; products without a category go to an "Tanpa Kategori"
  /// section. When a search query is active only matching products appear, but
  /// grouping is preserved.
  Widget _buildProductList() {
    if (_products.isEmpty) {
      return const Center(child: Text('Produk tidak ditemukan.'));
    }

    final sections = <(String, List<Product>)>[];

    for (final cat in _categories) {
      final items = _productsByCategory[cat.id];
      if (items != null && items.isNotEmpty) {
        sections.add((cat.name, items));
      }
    }
    if (_uncategorized.isNotEmpty) {
      sections.add(('Tanpa Kategori', _uncategorized));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListView(
        children: [
          for (final (title, items) in sections) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Row(
                children: [
                  Icon(Icons.folder_outlined,
                      size: 18, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    ' (${items.length})',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            LayoutBuilder(
                builder: (context, gridConstraints) {
                  const tileWidth = 150.0;
                  final columns = (gridConstraints.maxWidth / tileWidth)
                      .floor()
                      .clamp(1, 6);
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final product = items[index];
                      return ProductGridCard(
                        product: product,
                        onTap: () => _addToCart(product),
                      );
                    },
                  );
                },
              ),
          ],
        ],
      ),
    );
  }

  // ---------------- Cart (wide panel) ----------------
  Widget _buildCartPanel() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Keranjang ($_totalItems)',
                    style: Theme.of(context).textTheme.titleMedium),
                IconButton(
                  icon: const Icon(Icons.delete_sweep),
                  tooltip: 'Kosongkan',
                  onPressed: _cart.isEmpty ? null : _clearCart,
                ),
              ],
            ),
          ),
          Expanded(child: _buildCartList()),
          const Divider(height: 1),
          _buildPaymentSection(),
        ],
      ),
    );
  }

  Widget _buildCartList() {
    if (_cart.isEmpty) {
      return const Center(
        child: Text('Belum ada item di keranjang.',
            style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: _cart.length,
      itemBuilder: (context, index) {
        final item = _cart[index];
        final product = item.product;
        return _CartItemCard(
          product: product,
          quantity: item.quantity,
          onDecrease: () => _decreaseCartItem(index),
          onIncrease: () => _increaseCartItem(product),
          onRemove: () => _removeAllFromCart(product),
        );
      },
    );
  }

  // ---------------- Admin fee dropdown (shared by panel & modal) ----------------
  Widget _buildAdminFeeEditor({VoidCallback? onChanged}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.savings_outlined, size: 20, color: scheme.primary),
            const SizedBox(width: 8),
            Text(
              'Biaya Admin',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          initialValue: _selectedAdminFeeId,
          isExpanded: true,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: scheme.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          items: _adminFees.map((f) {
            return DropdownMenuItem(
              value: f.id,
              child: Text(
                f.amount > 0 ? '${f.name} (+${formatRupiah(f.amount)})' : f.name,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: _adminFees.isEmpty
              ? null
              : (id) {
                  setState(() => _selectedAdminFeeId = id);
                  onChanged?.call();
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
      ],
    );
  }

  // ---------------- Discount / voucher editor (shared by panel & modal) ----------------
  Widget _buildDiscountEditor({VoidCallback? onChanged}) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.local_offer_outlined, size: 20, color: scheme.primary),
            const SizedBox(width: 8),
            Text(
              'Diskon / Voucher',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            if (_hasDiscount)
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close, size: 18, color: Colors.red),
                tooltip: 'Hapus diskon',
                onPressed: () {
                  setState(() {
                    _discountPercent = null;
                    _discountRupiah = null;
                  });
                  onChanged?.call();
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _cart.isEmpty
              ? null
              : () => _showDiscountDialog(onChanged: onChanged),
          icon: const Icon(Icons.add_circle_outline),
          label: Text(
            _hasDiscount
                ? '$_discountLabel  (-${formatRupiah(_discount)})'
                : 'Tambahkan diskon / voucher',
            overflow: TextOverflow.ellipsis,
          ),
          style: OutlinedButton.styleFrom(
            alignment: Alignment.centerLeft,
            backgroundColor: scheme.surface,
            side: BorderSide(color: scheme.outlineVariant),
          ),
        ),
      ],
    );
  }

  Future<void> _showDiscountDialog({VoidCallback? onChanged}) async {
    final percentController = TextEditingController(
      text: (_discountPercent ?? 0) > 0
          ? _formatDouble(_discountPercent!)
          : '',
    );
    final rupiahController = TextEditingController(
      text: (_discountRupiah ?? 0) > 0
          ? (_discountRupiah!.round()).toString()
          : '',
    );
    var type = (_discountRupiah ?? 0) > 0 ? 'rupiah' : 'percent';
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Diskon / Voucher'),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'percent',
                        icon: Icon(Icons.percent),
                        label: Text('Persen'),
                      ),
                      ButtonSegment(
                        value: 'rupiah',
                        icon: Icon(Icons.payments_outlined),
                        label: Text('Rupiah'),
                      ),
                    ],
                    selected: {type},
                    onSelectionChanged: (selection) {
                      setDialogState(() => type = selection.first);
                    },
                  ),
                  const SizedBox(height: 16),
                  if (type == 'percent')
                    TextFormField(
                      controller: percentController,
                      autofocus: true,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Persentase diskon (%)',
                        prefixText: '% ',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final value = double.tryParse(v ?? '');
                        if (value == null) return 'Masukkan angka';
                        if (value <= 0 || value > 100) {
                          return 'Antara 1 - 100';
                        }
                        return null;
                      },
                    )
                  else
                    TextFormField(
                      controller: rupiahController,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Nominal potongan (Rp)',
                        prefixText: 'Rp ',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final value = double.tryParse(v ?? '');
                        if (value == null) return 'Masukkan angka';
                        if (value <= 0) return 'Harus lebih dari 0';
                        if (value > _subtotal) {
                          return 'Maksimal ${formatRupiah(_subtotal)}';
                        }
                        return null;
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(context, type);
              },
              child: const Text('Terapkan'),
            ),
          ],
        ),
      ),
    );

    if (result == null || result.isEmpty) return;
    final isPercent = result == 'percent';
    final rawValue = isPercent
        ? percentController.text
        : rupiahController.text;
    percentController.dispose();
    rupiahController.dispose();

    final value = double.tryParse(rawValue);
    if (value == null) return;
    setState(() {
      if (isPercent) {
        _discountPercent = value;
        _discountRupiah = null;
      } else {
        _discountRupiah = value;
        _discountPercent = null;
      }
    });
    onChanged?.call();
  }

  String _formatDouble(double v) {
    return v.truncateToDouble() == v ? v.toInt().toString() : v.toString();
  }

  Widget _buildPaymentSection() {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAdminFeeEditor(),
          const Divider(height: 16),
          _buildDiscountEditor(),
          const Divider(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Subtotal'),
              Text(formatRupiah(_subtotal)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Biaya Admin'),
              Text(formatRupiah(_adminFee)),
            ],
          ),
          if (_hasDiscount) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Diskon', style: TextStyle(color: scheme.error)),
                Text(
                  '- ${formatRupiah(_discount)}',
                  style: TextStyle(
                      color: scheme.error, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: Theme.of(context).textTheme.titleLarge),
              Text(
                formatRupiah(_total),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: scheme.primary, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _cart.isEmpty ? null : _checkout,
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Bayar', style: TextStyle(fontSize: 16)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomSummaryBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('$_totalItems item',
                      style: Theme.of(context).textTheme.bodySmall),
                  Text(
                    formatRupiah(_total),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: scheme.primary, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _cart.isEmpty ? null : _openCartModal,
                      icon: const Icon(Icons.remove_shopping_cart_outlined),
                      label: const Text('Keranjang'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _cart.isEmpty ? null : _checkout,
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Bayar',
                          style: TextStyle(fontSize: 16)),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- Cart modal (portrait) ----------------
  Future<void> _openCartModal() async {
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: scheme.surfaceContainerHighest,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final height = MediaQuery.of(context).size.height * 0.80;
        // A dedicated StatefulBuilder so EVERY cart/tax change can rebuild the
        // sheet immediately together with the parent state.
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void refresh() {
              // Rebuild the sheet contents AND the underlying screen in one go.
              setSheetState(() {});
              if (mounted) setState(() {});
            }

            return SafeArea(
              child: SizedBox(
                height: height,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Text('Keranjang ($_totalItems)',
                              style:
                                  Theme.of(context).textTheme.titleLarge),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.delete_sweep),
                            onPressed: _cart.isEmpty
                                ? null
                                : () {
                                    _clearCart();
                                    refresh();
                                  },
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _cart.isEmpty
                          ? const Center(
                              child: Text('Belum ada item di keranjang.',
                                  style: TextStyle(color: Colors.grey)),
                            )
                          : ListView.builder(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              itemCount: _cart.length,
                              itemBuilder: (context, index) {
                                final item = _cart[index];
                                return _CartItemCard(
                                  product: item.product,
                                  quantity: item.quantity,
                                  onDecrease: () {
                                    _decreaseCartItem(index);
                                    refresh();
                                  },
                                  onIncrease: () {
                                    _increaseCartItem(item.product);
                                    refresh();
                                  },
                                  onRemove: () {
                                    _removeAllFromCart(item.product);
                                    refresh();
                                  },
                                );
                              },
                            ),
                    ),
                    const Divider(height: 1),
                    _buildModalPaymentSection(refresh),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildModalPaymentSection(VoidCallback refresh) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAdminFeeEditor(onChanged: () => refresh()),
          const Divider(height: 12),
          _buildDiscountEditor(onChanged: () => refresh()),
          const Divider(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Subtotal'),
              Text(formatRupiah(_subtotal)),
            ],
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Biaya Admin'),
              Text(formatRupiah(_adminFee)),
            ],
          ),
          if (_hasDiscount) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Diskon', style: TextStyle(color: scheme.error)),
                Text(
                  '- ${formatRupiah(_discount)}',
                  style: TextStyle(
                      color: scheme.error, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ],
          const Divider(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total', style: Theme.of(context).textTheme.titleLarge),
              Text(
                formatRupiah(_total),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: scheme.primary, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _cart.isEmpty ? null : _checkout,
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Bayar', style: TextStyle(fontSize: 16)),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartItemCard extends StatelessWidget {
  final Product product;
  final int quantity;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;
  final VoidCallback onRemove;

  const _CartItemCard({
    required this.product,
    required this.quantity,
    required this.onDecrease,
    required this.onIncrease,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    product.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: onRemove,
                ),
              ],
            ),
            Row(
              children: [
                Text(formatRupiah(product.price),
                    style: const TextStyle(fontSize: 13)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: onDecrease,
                ),
                Text('$quantity',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: onIncrease,
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                formatRupiah(product.price * quantity),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentDetails {
  final PaymentMethod method;
  final String? buyerName;
  final double cashAmount;
  final String? paymentDetail;

  _PaymentDetails({
    required this.method,
    this.buyerName,
    required this.cashAmount,
    this.paymentDetail,
  });
}

class _CartItem {
  final Product product;
  final int quantity;

  _CartItem({required this.product, required this.quantity});
}