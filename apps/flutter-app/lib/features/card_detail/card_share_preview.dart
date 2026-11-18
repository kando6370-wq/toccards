import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../shared/ui/kando_modal.dart';
import '../../shared/ui/kando_style.dart';
import '../../shared/ui/toast.dart';

Future<bool> showCardSharePreview(
  BuildContext context, {
  required Uri cardUrl,
  required Future<Uint8List> posterBytes,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => KandoModalFrame(
          child: _CardSharePreview(cardUrl: cardUrl, posterBytes: posterBytes),
        ),
      ) ??
      false;
}

class _CardSharePreview extends StatelessWidget {
  const _CardSharePreview({required this.cardUrl, required this.posterBytes});

  final Uri cardUrl;
  final Future<Uint8List> posterBytes;

  Future<void> _copyLink(BuildContext context) async {
    try {
      await Clipboard.setData(ClipboardData(text: cardUrl.toString()));
      if (!context.mounted) return;
      showKandoTopToast(
        context,
        message: 'Link copied.',
        type: KandoTopToastType.success,
      );
    } on Object {
      if (context.mounted) showKandoTopFailureToast(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('card-share-preview-scroll'),
      child: Padding(
        key: const Key('card-share-preview-modal'),
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                key: const Key('card-share-preview-close'),
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.close, size: 20),
                color: KandoColors.mutedText,
              ),
            ),
            FutureBuilder<Uint8List>(
              future: posterBytes,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                final ready =
                    snapshot.connectionState == ConnectionState.done &&
                    snapshot.hasError == false &&
                    bytes != null &&
                    bytes.isNotEmpty;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 276,
                      height: 360,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: KandoColors.ink,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: KandoColors.borderSubtle),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: ready
                              ? Image.memory(
                                  bytes,
                                  key: const Key('card-share-preview-image'),
                                  fit: BoxFit.contain,
                                  filterQuality: FilterQuality.high,
                                  gaplessPlayback: true,
                                )
                              : snapshot.connectionState != ConnectionState.done
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    key: Key('card-share-preview-loading'),
                                    strokeWidth: 2,
                                    color: KandoColors.accent,
                                  ),
                                )
                              : const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Text(
                                      'Poster could not be generated.',
                                      key: Key('card-share-preview-error'),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        height: 18 / 13,
                                        color: KandoColors.mutedText,
                                      ),
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    KandoModalButton(
                      key: const Key('card-share-preview-submit'),
                      label: 'SHARE POSTER',
                      onPressed: ready
                          ? () => Navigator.of(context).pop(true)
                          : null,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            KandoModalButton(
              key: const Key('card-share-preview-copy-link'),
              label: 'COPY LINK',
              type: KandoModalButtonType.secondary,
              onPressed: () => _copyLink(context),
            ),
          ],
        ),
      ),
    );
  }
}
