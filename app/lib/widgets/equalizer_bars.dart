import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class EqualizerBars extends StatefulWidget {
  final Color color;
  final double width;
  final double height;

  const EqualizerBars({
    super.key,
    this.color = AppColors.accent,
    this.width = 16,
    this.height = 14,
  });

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return SizedBox(
          width: widget.width,
          height: widget.height,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (i) {
              final phase = _controller.value * 2 * pi + i * 0.8;
              final h = widget.height * (0.35 + 0.65 * ((sin(phase) + 1) / 2));
              return AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                width: 3,
                height: h,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(1.5),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
