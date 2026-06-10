import 'package:flutter/material.dart';

typedef InvalidConfigValueHandler = void Function(
  BuildContext context,
  String message,
);

class ImageConfigSliderSpec {
  final String label;
  final String editTitle;
  final String editTooltip;
  final String inputLabel;
  final double value;
  final ValueChanged<double> onChanged;
  final bool allowOutOfRangeDialogValue;
  final InvalidConfigValueHandler? onInvalidValue;

  const ImageConfigSliderSpec({
    required this.label,
    required this.editTitle,
    required this.editTooltip,
    required this.inputLabel,
    required this.value,
    required this.onChanged,
    this.allowOutOfRangeDialogValue = false,
    this.onInvalidValue,
  });
}

class ImageConfigRowCard extends StatelessWidget {
  final Widget thumbnail;
  final String fileName;
  final List<ImageConfigSliderSpec> sliders;
  final VoidCallback? onDelete;

  const ImageConfigRowCard({
    super.key,
    required this.thumbnail,
    required this.fileName,
    required this.sliders,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 120,
              width: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: thumbnail,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  for (final (index, slider) in sliders.indexed) ...[
                    if (index > 0) const SizedBox(height: 4),
                    _EditableConfigSlider(spec: slider),
                  ],
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                icon: Icon(Icons.delete_outline, color: Colors.red[700]),
                tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}

class _EditableConfigSlider extends StatelessWidget {
  final ImageConfigSliderSpec spec;

  const _EditableConfigSlider({required this.spec});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${spec.label}: ${spec.value.toStringAsFixed(2)}'),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: spec.value.clamp(0.0, 1.0),
                min: 0,
                max: 1,
                divisions: 100,
                label: spec.value.toStringAsFixed(2),
                onChanged: spec.onChanged,
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_note),
              tooltip: spec.editTooltip,
              onPressed: () => _showEditDialog(context),
            ),
          ],
        ),
      ],
    );
  }

  void _showEditDialog(BuildContext context) {
    final controller = TextEditingController(
      text: spec.value.toStringAsFixed(2),
    );
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(spec.editTitle),
          content: TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: spec.inputLabel),
            autofocus: true,
          ),
          actions: [
            TextButton(
              child: const Text('取消'),
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
            TextButton(
              child: const Text('确定'),
              onPressed: () {
                final newValue = double.tryParse(controller.text);
                if (_isValidDialogValue(newValue)) {
                  spec.onChanged(newValue!);
                  Navigator.of(dialogContext).pop();
                  return;
                }
                final message = '数值无效，请输入 0.0 到 1.0 之间的数字。';
                final handler = spec.onInvalidValue;
                if (handler != null) {
                  handler(context, message);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(message)),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  bool _isValidDialogValue(double? value) {
    if (value == null) return false;
    if (spec.allowOutOfRangeDialogValue) return true;
    return value >= 0 && value <= 1;
  }
}
