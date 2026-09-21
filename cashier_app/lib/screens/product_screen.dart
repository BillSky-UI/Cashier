import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../database/database_helper.dart';
import '../models/category.dart';
import '../models/product.dart';
import '../services/app_bus.dart';
import '../utils/format.dart';

class ProductScreen extends StatefulWidget {
  const ProductScreen({super.key});

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  final _searchController = TextEditingController();
  List<Product> _products = [];
  List<Category> _categories = [];
  bool _loading = true;
  bool _lowStockOnly = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
    AppBus.instance.addListener(_loadCategoriesOnly);
  }

  @override
  void dispose() {
    AppBus.instance.removeListener(_loadCategoriesOnly);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCategoriesOnly() async {
    final categories = await DatabaseHelper.instance.getCategories();
    if (mounted) {
      setState(() => _categories = categories);
    }
  }

  Future<void> _loadProducts() async {
    setState(() => _loading = true);
    final products =
        await DatabaseHelper.instance.getProducts(searchQuery: _searchController.text);
    final categories = await DatabaseHelper.instance.getCategories();
    if (mounted) {
      setState(() {
        _products = _lowStockOnly
            ? products
                .where((p) => p.isOutOfStock || p.isLowStock)
                .toList()
            : products;
        _categories = categories;
        _loading = false;
      });
    }
  }

  Future<void> _openAddEditDialog({Product? product}) async {
    await showDialog(
      context: context,
      builder: (_) => _ProductFormDialog(
        product: product,
        categories: _categories,
        onSave: () {
          _loadProducts();
          AppBus.instance.notifyChanged();
        },
      ),
    );
  }

  Future<void> _confirmDelete(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Produk'),
        content: Text('Yakin ingin menghapus "${product.name}"?'),
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
      await DatabaseHelper.instance.deleteProduct(product.id!);
      _loadProducts();
      AppBus.instance.notifyChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manajemen Produk'),
        actions: [
          IconButton(
            tooltip: 'Tambah Produk',
            icon: const Icon(Icons.add),
            onPressed: () => _openAddEditDialog(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddEditDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Tambah Produk'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => _loadProducts(),
              decoration: InputDecoration(
                hintText: 'Cari produk...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _loadProducts();
                        },
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                avatar: const Icon(Icons.warning_amber_rounded, size: 18),
                label: Text(
                  _lowStockOnly ? 'Stok menipis / habis' : 'Tampilkan stok menipis',
                ),
                selected: _lowStockOnly,
                onSelected: (selected) {
                  setState(() => _lowStockOnly = selected);
                  _loadProducts();
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _products.isEmpty
                    ? const Center(
                        child: Text(
                          'Belum ada produk.\nTambahkan produk terlebih dahulu.',
                          textAlign: TextAlign.center,
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadProducts,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            const tileWidth = 220.0;
                            final columns = (constraints.maxWidth / tileWidth)
                                .floor()
                                .clamp(1, 6);
                            return Center(
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 1200),
                                child: GridView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      12, 4, 12, 88),
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: columns,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                    childAspectRatio: 1.05,
                                  ),
                                  itemCount: _products.length,
                                  itemBuilder: (context, index) {
                                    final product = _products[index];
                                    final lowStock =
                                        product.isLowStock || product.isOutOfStock;
                                    final warnColor = product.isLowStock
                                        ? Colors.amber.shade800
                                        : Theme.of(context).colorScheme.error;
                                    return Card(
                                      clipBehavior: Clip.antiAlias,
                                      child: Stack(
                                        children: [
                                          InkWell(
                                            onTap: () => _openAddEditDialog(
                                                product: product),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.all(12),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: CircleAvatar(
                                                          child: Text(
                                                            product.name
                                                                    .isNotEmpty
                                                                ? product
                                                                    .name[0]
                                                                    .toUpperCase()
                                                                : '?',
                                                          ),
                                                        ),
                                                      ),
                                                      IconButton(
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        icon: const Icon(
                                                            Icons.edit,
                                                            size: 20),
                                                        onPressed: () =>
                                                            _openAddEditDialog(
                                                                product:
                                                                    product),
                                                      ),
                                                      IconButton(
                                                        visualDensity:
                                                            VisualDensity
                                                                .compact,
                                                        icon: const Icon(
                                                            Icons.delete,
                                                            size: 20,
                                                            color: Colors.red),
                                                        onPressed: () =>
                                                            _confirmDelete(
                                                                product),
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    product.name,
                                                    maxLines: 2,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600),
                                                  ),
                                                  const Spacer(),
                                                  Text(
                                                    formatRupiah(product.price),
                                                    style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .primary),
                                                  ),
                                                  Text(
                                                    product.isOutOfStock
                                                        ? 'Stok habis'
                                                        : 'Stok: ${product.stock}',
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: lowStock
                                                            ? FontWeight.w600
                                                            : null,
                                                        color: lowStock
                                                            ? warnColor
                                                            : null,
                                                      ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          if (lowStock)
                                            Positioned(
                                              top: 4,
                                              right: 4,
                                              child: Badge(
                                                backgroundColor: warnColor,
                                                label: const Text('',
                                                    style: TextStyle(
                                                        fontSize: 10)),
                                                smallSize: 12,
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _ProductFormDialog extends StatefulWidget {
  final Product? product;
  final List<Category> categories;
  final VoidCallback onSave;

  const _ProductFormDialog({
    required this.product,
    required this.categories,
    required this.onSave,
  });

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<_ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late final TextEditingController _costController;
  late final TextEditingController _stockController;

  int? _categoryId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameController = TextEditingController(text: p?.name ?? '');
    _priceController =
        TextEditingController(text: p?.price.toString() ?? '');
    _costController = TextEditingController(
        text: p != null && p.costPrice > 0 ? p.costPrice.toString() : '');
    _stockController =
        TextEditingController(text: p?.stock.toString() ?? '');
    _categoryId = p?.categoryId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _costController.dispose();
    _stockController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final product = Product(
      id: widget.product?.id,
      name: _nameController.text.trim(),
      price: double.parse(_priceController.text),
      costPrice: double.tryParse(_costController.text.trim()) ?? 0,
      stock: int.parse(_stockController.text),
      categoryId: _categoryId,
    );

    if (widget.product == null) {
      await DatabaseHelper.instance.insertProduct(product);
    } else {
      await DatabaseHelper.instance.updateProduct(product);
    }

    if (mounted) {
      Navigator.pop(context);
      widget.onSave();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.product != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Produk' : 'Tambah Produk'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Nama Produk',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Nama wajib diisi' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceController,
                decoration: const InputDecoration(
                  labelText: 'Harga',
                  prefixText: 'Rp ',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Harga wajib diisi';
                  final value = double.tryParse(v);
                  if (value == null || value <= 0) return 'Harga tidak valid';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _costController,
                decoration: const InputDecoration(
                  labelText: 'Harga Modal (opsional)',
                  prefixText: 'Rp ',
                  helperText: 'Harga beli/pokok produk. Kosongkan jika tidak tahu.',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (v == null || v.isEmpty) return null;
                  final value = double.tryParse(v);
                  if (value == null || value < 0) return 'Modal tidak valid';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _stockController,
                decoration: const InputDecoration(
                  labelText: 'Stok',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Stok wajib diisi';
                  if (int.tryParse(v) == null) return 'Stok tidak valid';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Kategori',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const SizedBox(height: 4),
              DropdownButtonFormField<int?>(
                initialValue: _categoryId,
                isExpanded: true,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 14),
                ),
                hint: const Text('Tanpa Kategori'),
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('Tanpa Kategori'),
                  ),
                  for (final cat in widget.categories)
                    DropdownMenuItem<int?>(
                      value: cat.id,
                      child: Text(cat.name,
                          overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => setState(() => _categoryId = value),
              ),
              if (widget.categories.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Belum ada kategori. Tambahkan lewat Pengaturan > Kategori.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
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
