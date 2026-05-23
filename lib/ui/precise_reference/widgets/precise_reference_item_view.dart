import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../viewmodels/precise_reference_item_viewmodel.dart';

class PreciseReferenceItemView extends StatelessWidget {
  final PreciseReferenceItemViewmodel viewmodel;
  final VoidCallback? onDelete;

  const PreciseReferenceItemView({
    super.key,
    required this.viewmodel,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final thumbnail = viewmodel.imageBytes != null
        ? Image.memory(
            viewmodel.imageBytes!,
            fit: BoxFit.cover,
          )
        : const Icon(Icons.broken_image_outlined, size: 50);

    final typeOptions = const [
      'character&style',
      'character',
      'style',
    ];

    final typeLabel = {
      'character&style': tr('precise_reference_type_character_style'),
      'character': tr('precise_reference_type_character'),
      'style': tr('precise_reference_type_style'),
    };

    return ListenableBuilder(
      listenable: viewmodel,
      builder: (context, _) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: thumbnail,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        viewmodel.fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(tr('precise_reference_type')),
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: viewmodel.type,
                            items: typeOptions
                                .map(
                                  (value) => DropdownMenuItem(
                                    value: value,
                                    child: Text(typeLabel[value] ?? value),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) return;
                              viewmodel.setType(value);
                            },
                          )
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${tr('precise_reference_strength')}: ${viewmodel.strength.toStringAsFixed(2)}',
                      ),
                      Slider(
                        min: 0,
                        max: 1,
                        divisions: 100,
                        value: viewmodel.strength,
                        onChanged: viewmodel.setStrength,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${tr('precise_reference_fidelity')}: ${viewmodel.fidelity.toStringAsFixed(2)}',
                      ),
                      Slider(
                        min: 0,
                        max: 1,
                        divisions: 100,
                        value: viewmodel.fidelity,
                        onChanged: viewmodel.setFidelity,
                      ),
                    ],
                  ),
                ),
                if (onDelete != null)
                  IconButton(
                    icon: Icon(
                      Icons.delete_outline,
                      color: Colors.red[700],
                    ),
                    tooltip: tr('delete_config'),
                    onPressed: onDelete,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
