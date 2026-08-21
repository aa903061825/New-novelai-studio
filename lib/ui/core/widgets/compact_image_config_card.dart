import 'package:flutter/material.dart';

class CompactImageConfigCard extends StatelessWidget {
  static const cardRadius = BorderRadius.only(
    topLeft: Radius.circular(8),
    topRight: Radius.circular(8),
    bottomLeft: Radius.circular(8),
  );

  final Widget thumbnail;
  final String fileName;
  final VoidCallback onDelete;
  final List<Widget> controls;
  final double height;

  const CompactImageConfigCard({
    super.key,
    required this.thumbnail,
    required this.fileName,
    required this.onDelete,
    required this.controls,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 128,
      height: height,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: cardRadius,
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  thumbnail,
                  Positioned(
                    top: 2,
                    right: 2,
                    child: IconButton(
                      tooltip:
                          MaterialLocalizations.of(context).deleteButtonTooltip,
                      iconSize: 18,
                      visualDensity: VisualDensity.compact,
                      onPressed: onDelete,
                      icon: const Icon(Icons.close),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  ...controls,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class MiniLabeledSlider extends StatelessWidget {
  final String label;
  final double value;
  final ValueChanged<double>? onChanged;

  const MiniLabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            '$label ${value.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(0.0, 1.0),
            min: 0,
            max: 1,
            divisions: 100,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class CompactAddImageCard extends StatelessWidget {
  final VoidCallback onTap;

  const CompactAddImageCard({
    super.key,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 128,
      height: 156,
      child: InkWell(
        borderRadius: CompactImageConfigCard.cardRadius,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: CompactImageConfigCard.cardRadius,
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: const Center(
            child: Icon(Icons.add_photo_alternate_outlined, size: 40),
          ),
        ),
      ),
    );
  }
}
