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
    this.blurSigma = 30,
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
    final url = widget.imageUrl;
    if (url == null) return;
    try {
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted || widget.imageUrl != url) return;
      final palette = await PaletteGenerator.fromImageProvider(
        ResizeImage(CachedNetworkImageProvider(url), width: 64),
        maximumColorCount: 8,
      );
      if (!mounted || widget.imageUrl != url) return;
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
        RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
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
                      memCacheWidth: 120,
                      fadeInDuration: Duration.zero,
                      errorWidget: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
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
            ],
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
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: AppColors.surface),
          if (imageUrl != null)
            CachedNetworkImage(
              imageUrl: imageUrl!,
              fit: BoxFit.cover,
              memCacheWidth: 600,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.background.withValues(alpha: 0.15),
                  AppColors.background.withValues(alpha: 0.55),
                  AppColors.background,
                ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
