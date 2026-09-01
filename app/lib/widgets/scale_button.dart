import 'package:flutter/material.dart';

class ScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final double scale;

  const ScaleButton({
    super.key,
    required this.child,
    this.onPressed,
    this.scale = 0.92,
  });

  @override
  State<ScaleButton> createState() => _ScaleButtonState();
}

class _ScaleButtonState extends State<ScaleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onPressed != null ? (_) => setState(() => _pressed = true) : null,
      onTapUp: widget.onPressed != null ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: widget.onPressed != null ? () => setState(() => _pressed = false) : null,
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
