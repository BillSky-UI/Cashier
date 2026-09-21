class Category {
  final int? id;
  final String name;
  final int orderIndex;

  Category({this.id, required this.name, this.orderIndex = 0});

  Category copyWith({String? name, int? orderIndex}) {
    return Category(
      id: id,
      name: name ?? this.name,
      orderIndex: orderIndex ?? this.orderIndex,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'order_index': orderIndex,
    };
  }

  factory Category.fromMap(Map<String, dynamic> map) {
    return Category(
      id: map['id'],
      name: map['name'],
      orderIndex: map['order_index'] ?? 0,
    );
  }
}