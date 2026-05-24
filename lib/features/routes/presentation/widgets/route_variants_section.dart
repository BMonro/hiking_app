import 'package:flutter/material.dart';

import '../../domain/route_model.dart';
import '../../domain/route_variant.dart';

class RouteVariantsSection extends StatelessWidget {
  const RouteVariantsSection({
    super.key,
    required this.variants,
    required this.loading,
    required this.selectedIndex,
    required this.onSuggest,
    required this.onSelect,
    this.disabled = false,
  });

  final List<RouteVariant> variants;
  final bool loading;
  final int? selectedIndex;
  final VoidCallback? onSuggest;
  final ValueChanged<int> onSelect;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: (disabled || loading) ? null : onSuggest,
          icon: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.alt_route_outlined),
          label: Text(
            loading ? 'Побудова варіантів…' : 'Запропонувати варіанти',
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF2E7D32),
            side: const BorderSide(color: Color(0xFF2E7D32)),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        if (variants.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            'Оберіть варіант (складність — за км, набором висоти та часом). '
            'Якщо лише один — у цій зоні роутер не знайшов інших стежок.',
            style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.35),
          ),
          const SizedBox(height: 8),
          ...List.generate(variants.length, (i) {
            final v = variants[i];
            final selected = selectedIndex == i;
            final color = RouteModel.difficultyColorFor(v.difficulty);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: selected
                    ? color.withValues(alpha: 0.12)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: disabled ? null : () => onSelect(i),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? color
                            : Colors.black.withValues(alpha: 0.08),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: selected ? color : Colors.grey,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: color.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      v.difficultyLabel,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                        color: color,
                                      ),
                                    ),
                                  ),
                                  if (variants.length > 1) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      'Варіант ${i + 1}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${v.distanceKm.toStringAsFixed(1)} км · '
                                '${v.durationH.toStringAsFixed(1)} год · '
                                '${v.ascentM} м набір',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ],
    );
  }
}
