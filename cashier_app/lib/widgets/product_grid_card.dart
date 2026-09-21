import 'package:flutter/material.dart';

import '../models/product.dart';
import '../utils/format.dart';

class ProductGridCard extends StatelessWidget {
  final Product product;
  final VoidCallback onTap;

  const ProductGridCard({super.key, required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final outOfStock = product.isOutOfStock;
    final lowStock = product.isLowStock;
    final warnColor = lowStock ? Colors.amber.shade800 : scheme.error;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: outOfStock ? null : onTap,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: scheme.primaryContainer,
                    child: Text(
                      product.name.isNotEmpty
                          ? product.name[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                        fontSize: 20,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    formatRupiah(product.price),
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    outOfStock ? 'Stok habis' : 'Stok: ${product.stock}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          (lowStock || outOfStock) ? FontWeight.w600 : null,
                      color: outOfStock
                          ? scheme.error
                          : (lowStock
                              ? warnColor
                              : Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ),
            if (lowStock || outOfStock)
              Positioned(
                top: 4,
                right: 4,
                child: Badge(
                  backgroundColor: warnColor,
                  label: const Text('', style: TextStyle(fontSize: 10)),
                  smallSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
