import 'package:flutter/material.dart';

const _placeholderAsset = 'assets/home/trend_placeholder.png';

class KandoCardImage extends StatelessWidget {
  const KandoCardImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    this.semanticLabel,
    this.webHtmlElementStrategy = WebHtmlElementStrategy.prefer,
    this.filterQuality = FilterQuality.high,
    this.placeholderKey,
  });

  final String? imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final String? semanticLabel;
  final WebHtmlElementStrategy webHtmlElementStrategy;
  final FilterQuality filterQuality;
  final Key? placeholderKey;

  @override
  Widget build(BuildContext context) {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) return _placeholder();

    return Image.network(
      url,
      width: width ?? double.infinity,
      height: height ?? double.infinity,
      fit: fit,
      webHtmlElementStrategy: webHtmlElementStrategy,
      filterQuality: filterQuality,
      semanticLabel: semanticLabel,
      errorBuilder: (_, _, _) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return Image.asset(
      _placeholderAsset,
      key: placeholderKey,
      width: width ?? double.infinity,
      height: height ?? double.infinity,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );
  }
}
