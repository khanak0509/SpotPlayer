import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import '../theme/app_theme.dart';

class ArtBackground extends StatefulWidget {
  final String? imageUrl;
  final Widget child;
  final double blurSigma;

  const ArtBackground({
    super.key,
    this.imageUrl,
    required this.child,
    this.blurSigma = 60,
  });

  @override
  State<ArtBackground> createState() => _ArtBackgroundState();
}

class _ArtBackgroundState extends State<ArtBackground> {
  Color _dominant = AppColors.surface;
  Color _accent = AppColors.accent.withValues(alpha: 0.3);

  @override
  void initState() {
    super.initState();
    _extractColors();
  }

  @override
  void didUpdateWidget(ArtBackground old) {
    super.didUpdateWidget(old);
    if (old.imageUrl != widget.imageUrl) _extractColors();
  }

  Future<void> _extractColors() async {
    if (widget.imageUrl == null) return;
    try {
      final palette = await PaletteGenerator.fromImageProvider(
        CachedNetworkImageProvider(widget.imageUrl!),
        maximumColorCount: 8,
      );
      if (!mounted) return;
      setState(() {
        _dominant = palette.dominantColor?.color ?? AppColors.surface;
        _accent = (palette.vibrantColor ?? palette.mutedColor)?.color
                .withValues(alpha: 0.35) ??
            AppColors.accent.withValues(alpha: 0.3);
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: AppColors.background),
        if (widget.imageUrl != null)
          ImageFiltered(
            imageFilter: ImageFilter.blur(
              sigmaX: widget.blurSigma,
              sigmaY: widget.blurSigma,
            ),
            child: Transform.scale(
              scale: 1.4,
              child: CachedNetworkImage(
                imageUrl: widget.imageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.lerp(_dominant, AppColors.background, 0.3)!.withValues(alpha: 0.85),
                Color.lerp(_accent, AppColors.background, 0.5)!.withValues(alpha: 0.95),
                AppColors.background,
              ],
              stops: const [0.0, 0.45, 1.0],
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class ArtGradientHeader extends StatelessWidget {
  final String? imageUrl;
  final double height;

  const ArtGradientHeader({super.key, this.imageUrl, this.height = 280});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ArtBackground(
        imageUrl: imageUrl,
        blurSigma: 50,
        child: const SizedBox.expand(),
      ),
    );
  }
}
