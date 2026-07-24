import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:kando_app/shared/currency/currency.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:kando_app/shared/ui/toast.dart';

import 'search_controller.dart';
import 'search_models.dart';

class SearchCardTile extends ConsumerWidget {
  const SearchCardTile({
    super.key,
    required this.card,
    required this.actionsEnabled,
    this.showActions = true,
    this.showSearchMetadata = false,
  });

  final SearchCard card;
  final bool actionsEnabled;
  final bool showActions;
  final bool showSearchMetadata;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(searchControllerProvider.notifier);
    final currency = ref.watch(selectedCurrencyProvider);
    final showFilledHeart = card.isWishlisted;
    final change = card.changeText;
    final changeColor = change.startsWith('-')
        ? Theme.of(context).colorScheme.error
        : (change.startsWith('+') ? KandoColors.accent : KandoColors.mutedText);

    const mutedLine = TextStyle(
      fontSize: 11,
      height: 18 / 11,
      color: KandoColors.mutedText,
    );

    return Material(
      key: Key('search-card-${card.id}'),
      color: KandoColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => context.push('/cards/${card.id}'),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: KandoColors.border),
          ),
          padding: const EdgeInsets.all(13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: Container(
                        key: Key('search-card-image-container-${card.id}'),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: KandoColors.ink,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: card.imageUrl == null
                            ? const Icon(
                                Icons.style_outlined,
                                color: KandoColors.mutedText,
                              )
                            : Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: AspectRatio(
                                  aspectRatio: 672 / 936,
                                  child: ClipRRect(
                                    key: Key(
                                      'search-card-image-clip-${card.id}',
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.network(
                                      card.imageUrl!,
                                      width: double.infinity,
                                      height: double.infinity,
                                      fit: BoxFit.cover,
                                      webHtmlElementStrategy:
                                          WebHtmlElementStrategy.fallback,
                                      semanticLabel: card.name,
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                            return const Icon(
                                              Icons.style_outlined,
                                              color: KandoColors.mutedText,
                                            );
                                          },
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ),
                    if (showActions)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Transform.translate(
                          offset: const Offset(0, -10),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {},
                            child: Row(
                              children: [
                                _SearchCardActionButton(
                                  key: Key('search-collect-${card.id}'),
                                  tooltip: card.isCollected
                                      ? 'Collected'
                                      : 'Collect',
                                  iconAsset: card.isCollected
                                      ? 'assets/search/collection_on.svg'
                                      : 'assets/search/collection_off.svg',
                                  onPressed: !actionsEnabled
                                      ? null
                                      : () async {
                                          final action = await controller
                                              .toggleCollectCard(card);
                                          if (action ==
                                              SearchCollectAction.openDetail) {
                                            if (context.mounted) {
                                              context.push('/cards/${card.id}');
                                            }
                                          } else if (action ==
                                                  SearchCollectAction.ignored &&
                                              context.mounted) {
                                            showKandoTopFailureToast(context);
                                          }
                                        },
                                ),
                                if (!card.isCollected) ...[
                                  const SizedBox(width: 8),
                                  _SearchCardActionButton(
                                    key: Key('search-wishlist-${card.id}'),
                                    tooltip: showFilledHeart
                                        ? 'Remove from wishlist'
                                        : 'Add to wishlist',
                                    iconAsset: showFilledHeart
                                        ? 'assets/search/wishlist_on.svg'
                                        : 'assets/search/wishlist_off.svg',
                                    onPressed: !actionsEnabled
                                        ? null
                                        : () async {
                                            final succeeded = await controller
                                                .toggleWishlistCard(card);
                                            if (!succeeded && context.mounted) {
                                              showKandoTopFailureToast(context);
                                            }
                                          },
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                showSearchMetadata ? _cardName(card) : card.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Fraunces',
                  fontSize: 14,
                  height: 20 / 14,
                  fontWeight: FontWeight.w600,
                  color: KandoColors.text,
                ),
              ),
              const SizedBox(height: 2),
              if (showSearchMetadata) ...[
                Text(
                  card.setName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mutedLine,
                ),
                Text(
                  _searchMetadataLine(card.metadataLine),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mutedLine,
                ),
                _MetadataRow(
                  left: card.collectionInfo ?? '',
                  right: card.variantLine,
                  style: mutedLine,
                ),
                _PriceRow(
                  quantity: card.quantity,
                  price: card.priceText(currency),
                  change: change,
                  changeColor: changeColor,
                  mutedStyle: mutedLine,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    change,
                    style: TextStyle(
                      fontSize: 10,
                      height: 14 / 10,
                      color: changeColor,
                    ),
                  ),
                ),
              ] else ...[
                Text(
                  card.setName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mutedLine,
                ),
                Text(
                  card.metadataLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mutedLine,
                ),
                if (card.variantLine.isNotEmpty)
                  Text(
                    card.variantLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mutedLine,
                  ),
                Text('Qty: ${card.quantity}', style: mutedLine),
                const SizedBox(height: 6),
                Text(
                  card.priceText(currency),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 24 / 14,
                    fontWeight: FontWeight.w600,
                    color: KandoColors.text,
                  ),
                ),
                Text(
                  change,
                  style: TextStyle(
                    fontSize: 10,
                    height: 14 / 10,
                    color: changeColor,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

String _cardName(SearchCard card) {
  final languageCode = _displayLanguageCode(card.language);
  return languageCode == null ? card.name : '${card.name} ($languageCode)';
}

String _searchMetadataLine(String value) {
  final metadata = value.trim();
  if (metadata.startsWith('#')) return metadata.substring(1);
  return metadata.replaceFirst(' #', ' · ');
}

String? _displayLanguageCode(String? value) {
  final language = value?.trim();
  if (language == null || language.isEmpty) return null;

  return switch (language.toLowerCase()) {
    'english' || 'en' || 'eng' => null,
    'japanese' || 'ja' || 'jp' => 'JP',
    'chinese' ||
    'simplified chinese' ||
    'traditional chinese' ||
    'zh' ||
    'cn' => 'CN',
    'korean' || 'ko' || 'kr' => 'KR',
    'french' || 'fr' => 'FR',
    'german' || 'de' => 'DE',
    'italian' || 'it' => 'IT',
    'spanish' || 'es' => 'ES',
    'portuguese' || 'pt' => 'PT',
    _ => language.length <= 3 ? language.toUpperCase() : language,
  };
}

class _MetadataRow extends StatelessWidget {
  const _MetadataRow({
    required this.left,
    required this.right,
    required this.style,
  });

  final String left;
  final String right;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            left,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: style,
          ),
        ),
      ],
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.quantity,
    required this.price,
    required this.change,
    required this.changeColor,
    required this.mutedStyle,
  });

  final int quantity;
  final String price;
  final String change;
  final Color changeColor;
  final TextStyle mutedStyle;

  @override
  Widget build(BuildContext context) {
    final icon = change.startsWith('-')
        ? Icons.trending_down
        : change.startsWith('+')
        ? Icons.trending_up
        : Icons.trending_flat;
    return Row(
      children: [
        Expanded(child: Text('Qty: $quantity', style: mutedStyle)),
        Icon(icon, size: 13, color: changeColor),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            price,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 14,
              height: 24 / 14,
              fontWeight: FontWeight.w600,
              color: KandoColors.text,
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchCardActionButton extends StatelessWidget {
  const _SearchCardActionButton({
    required this.tooltip,
    required this.iconAsset,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final String iconAsset;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
      padding: EdgeInsets.zero,
      icon: ClipOval(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 7.65, sigmaY: 7.65),
          child: SizedBox.square(
            dimension: 32,
            child: Stack(
              fit: StackFit.expand,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0x33FFFFFF),
                    shape: BoxShape.circle,
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0x33565555),
                    shape: BoxShape.circle,
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                      width: 0.5,
                    ),
                  ),
                ),
                Center(
                  child: SvgPicture.asset(
                    iconAsset,
                    key: ValueKey(iconAsset),
                    width: 16,
                    height: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
