import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  });

  final SearchCard card;
  final bool actionsEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(searchControllerProvider.notifier);
    final currency = ref.watch(selectedCurrencyProvider);
    final showFilledHeart = card.isWishlisted && !card.isCollected;
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
                  children: [
                    Positioned.fill(
                      child: Container(
                        key: Key('search-card-image-container-${card.id}'),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: KandoColors.ink,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: KandoColors.border),
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
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Row(
                        children: [
                          _SearchCardActionButton(
                            key: Key('search-collect-${card.id}'),
                            tooltip: card.isCollected ? 'Collected' : 'Collect',
                            icon: card.isCollected
                                ? Icons.add_to_photos
                                : Icons.add_to_photos_outlined,
                            selected: card.isCollected,
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
                                      showKandoFailureToast(context);
                                    }
                                  },
                          ),
                          const SizedBox(width: 8),
                          _SearchCardActionButton(
                            key: Key('search-wishlist-${card.id}'),
                            tooltip: showFilledHeart
                                ? 'Remove from wishlist'
                                : 'Add to wishlist',
                            icon: showFilledHeart
                                ? Icons.favorite
                                : Icons.favorite_border,
                            selected: showFilledHeart,
                            onPressed: !actionsEnabled
                                ? null
                                : () async {
                                    final succeeded = await controller
                                        .toggleWishlistCard(card);
                                    if (!succeeded && context.mounted) {
                                      showKandoFailureToast(context);
                                    }
                                  },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                card.name,
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
          ),
        ),
      ),
    );
  }
}

class _SearchCardActionButton extends StatelessWidget {
  const _SearchCardActionButton({
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? KandoColors.accent.withValues(alpha: 0.28)
            : KandoColors.elevatedSurface.withValues(alpha: 0.82),
        shape: BoxShape.circle,
        border: Border.all(color: KandoColors.borderSubtle, width: 0.5),
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: 16,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        padding: EdgeInsets.zero,
        color: selected ? KandoColors.accent : KandoColors.text,
        icon: Icon(icon),
      ),
    );
  }
}
