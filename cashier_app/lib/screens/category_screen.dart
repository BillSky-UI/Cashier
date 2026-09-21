import 'package:flutter/material.dart';

import '../database/database_helper.dart';
import '../models/category.dart';
import '../services/app_bus.dart';

class CategoryScreen extends StatefulWidget {
  const CategoryScreen({super.key});

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();
}

class _CategoryScreenState extends State<CategoryScreen> {
  List<Category> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final categories = await DatabaseHelper.instance.getCategories();
    if (mounted) {
      setState(() {
        _categories = categories;
        _loading = false;
      });
      AppBus.instance.notifyChanged();
    }
  }

  Future<void> _openForm({Category? category}) async {
    await showDialog(
      context: context,
      builder: (_) => _CategoryFormDialog(category: category, onSave: _load),
    );
  }

  Future<void> _confirmDelete(Category category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Kategori'),
        content: Text(
            'Hapus "${category.name}"? Produk dalam kategori ini akan menjadi "Tanpa Kategori".'),
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
      await DatabaseHelper.instance.deleteCategory(category.id!);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Kategori'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Tambah Kategori',
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
          : _categories.isEmpty
              ? const Center(
                  child: Text(
                    'Belum ada kategori.\nTambahkan untuk memulai.',
                    textAlign: TextAlign.center,
                  ),
                )
              : ReorderableListView(
                  onReorderItem: (oldIndex, newIndex) {
                    setState(() {
                      final item = _categories.removeAt(oldIndex);
                      _categories.insert(newIndex, item);
                    });
                    for (var i = 0; i < _categories.length; i++) {
                      DatabaseHelper.instance
                          .updateCategoryOrder(_categories[i].id!, i);
                    }
                    AppBus.instance.notifyChanged();
                  },
                  padding: const EdgeInsets.only(bottom: 88),
                  children: [
                    for (var i = 0; i < _categories.length; i++)
                      Card(
                        key: ValueKey(_categories[i].id),
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: ListTile(
                          title: Text(_categories[i].name),
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
                                onPressed: () =>
                                    _openForm(category: _categories[i]),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red),
                                tooltip: 'Hapus',
                                onPressed: () =>
                                    _confirmDelete(_categories[i]),
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

class _CategoryFormDialog extends StatefulWidget {
  final Category? category;
  final VoidCallback onSave;

  const _CategoryFormDialog({this.category, required this.onSave});

  @override
  State<_CategoryFormDialog> createState() => _CategoryFormDialogState();
}

class _CategoryFormDialogState extends State<_CategoryFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController =
        TextEditingController(text: widget.category?.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final category = Category(
      id: widget.category?.id,
      name: _nameController.text.trim(),
      orderIndex: widget.category?.orderIndex ?? 0,
    );

    if (widget.category == null) {
      await DatabaseHelper.instance.insertCategory(category);
    } else {
      await DatabaseHelper.instance.updateCategory(category);
    }

    if (mounted) {
      Navigator.pop(context);
      widget.onSave();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.category != null;
    return AlertDialog(
      title: Text(isEdit ? 'Edit Kategori' : 'Tambah Kategori'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _nameController,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Nama Kategori',
            hintText: 'Misal: Pakan Ayam',
            prefixIcon: Icon(Icons.folder_outlined),
            border: OutlineInputBorder(),
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Nama wajib diisi';
            return null;
          },
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