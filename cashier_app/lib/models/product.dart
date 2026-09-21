class Product {
  /// Products with stock below this positive threshold are considered "low
  /// stock" and get a warning badge in the UI.
  static const int lowStockThreshold = 5;

  final int? id;
  final String name;
  final double price;
  final double costPrice;
  final int stock;
  final String? category;

  /// Reference to the managed [Category] this product belongs to, if any.
  final int? categoryId;

  Product({
    this.id,
    required this.name,
    required this.price,
    this.costPrice = 0,
    required this.stock,
    this.category,
    this.categoryId,
  });

  bool get isOutOfStock => stock <= 0;

  bool get isLowStock => stock > 0 && stock < lowStockThreshold;

  Product copyWith({
    int? id,
    String? name,
    double? price,
    double? costPrice,
    int? stock,
    String? category,
    int? categoryId,
  }) {
    return Product(
      id: id ?? this.id,
      name: name ?? this.name,
      price: price ?? this.price,
      costPrice: costPrice ?? this.costPrice,
      stock: stock ?? this.stock,
      category: category ?? this.category,
      categoryId: categoryId ?? this.categoryId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'cost_price': costPrice,
      'stock': stock,
      'category': category,
      'category_id': categoryId,
    };
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    return Product(
      id: map['id'],
      name: map['name'],
      price: map['price'],
      costPrice: (map['cost_price'] as num?)?.toDouble() ?? 0,
      stock: map['stock'],
      category: map['category'],
      categoryId: map['category_id'] as int?,
    );
  }
}