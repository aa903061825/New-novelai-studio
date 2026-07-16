import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_scope.dart';
import 'package:novel_studio/ui/studio_core/motion/studio_motion_tokens.dart';

class StudioAnimatedNumber extends StatefulWidget {
  final int value;
  final int from;
  final Duration duration;
  final Curve curve;
  final String prefix;
  final String suffix;
  final String separator;
  final String? semanticLabel;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const StudioAnimatedNumber({
    super.key,
    required this.value,
    this.from = 0,
    this.duration = StudioMotionTokens.medium,
    this.curve = StudioMotionTokens.utilityCurve,
    this.prefix = '',
    this.suffix = '',
    this.separator = '',
    this.semanticLabel,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  State<StudioAnimatedNumber> createState() => _StudioAnimatedNumberState();
}

class _StudioAnimatedNumberState extends State<StudioAnimatedNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late double _from = widget.from.toDouble();
  late double _to = widget.value.toDouble();
  bool _started = false;
  bool _animationsDisabled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animationsDisabled = StudioMotionScope.animationsDisabled(context);
    _controller.duration = widget.duration;
    if (_animationsDisabled || widget.duration <= Duration.zero) {
      _from = widget.value.toDouble();
      _to = widget.value.toDouble();
      _controller.value = 1;
      _started = true;
      return;
    }
    if (!_started) {
      _started = true;
      _controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant StudioAnimatedNumber oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    if (oldWidget.value == widget.value) return;

    _from = _valueAt(_controller.value, oldWidget.curve);
    _to = widget.value.toDouble();
    if (_animationsDisabled || widget.duration <= Duration.zero) {
      _from = _to;
      _controller.value = 1;
    } else {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel ?? _format(widget.value),
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final value = _valueAt(_controller.value, widget.curve).round();
          return Text(
            _format(value),
            style: widget.style,
            textAlign: widget.textAlign,
            maxLines: widget.maxLines,
            overflow: widget.overflow,
          );
        },
      ),
    );
  }

  double _valueAt(double progress, Curve curve) {
    final transformed = curve.transform(progress.clamp(0.0, 1.0));
    return ui.lerpDouble(_from, _to, transformed) ?? _to;
  }

  String _format(int value) {
    final negative = value < 0;
    var digits = value.abs().toString();
    if (widget.separator.isNotEmpty) {
      final chunks = <String>[];
      while (digits.length > 3) {
        chunks.insert(0, digits.substring(digits.length - 3));
        digits = digits.substring(0, digits.length - 3);
      }
      chunks.insert(0, digits);
      digits = chunks.join(widget.separator);
    }
    final sign = negative ? '-' : '';
    return '${widget.prefix}$sign$digits${widget.suffix}';
  }
}
