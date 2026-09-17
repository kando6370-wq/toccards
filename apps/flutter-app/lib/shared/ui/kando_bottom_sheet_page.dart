import 'package:flutter/material.dart';

const _dragHandleAreaHeight = 32.0;

/// A declarative bottom-sheet page for GoRouter routes.
///
/// It uses Flutter's native modal bottom-sheet route so custom routed sheets
/// keep the same drag-to-dismiss behavior and motion as showModalBottomSheet.
class KandoBottomSheetPage<T> extends Page<T> {
  const KandoBottomSheetPage({
    required this.child,
    this.barrierColor = const Color(0xB8000000),
    this.isDismissible = true,
    this.enableDrag = true,
    this.useSafeArea = false,
    this.heightFactor,
    this.sheetAnimationStyle,
    super.key,
    super.name,
    super.arguments,
    super.restorationId,
  }) : assert(heightFactor == null || (heightFactor > 0 && heightFactor <= 1));

  final Widget child;
  final Color barrierColor;
  final bool isDismissible;
  final bool enableDrag;
  final bool useSafeArea;
  final double? heightFactor;
  final AnimationStyle? sheetAnimationStyle;

  @override
  Route<T> createRoute(BuildContext context) {
    final navigator = Navigator.of(context);
    final localizations = MaterialLocalizations.of(context);
    return ModalBottomSheetRoute<T>(
      settings: this,
      builder: (context) => Stack(
        alignment: Alignment.topCenter,
        children: [
          Semantics(
            label: MaterialLocalizations.of(context).modalBarrierDismissLabel,
            button: true,
            onTap: () => Navigator.of(context).pop(),
            child: SizedBox(
              key: const Key('kando-bottom-sheet-handle-area'),
              width: double.infinity,
              height: _dragHandleAreaHeight,
              child: Center(
                child: Container(
                  key: const Key('kando-bottom-sheet-handle'),
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: _dragHandleAreaHeight),
            child: heightFactor == null
                ? child
                : FractionallySizedBox(
                    alignment: Alignment.bottomCenter,
                    widthFactor: 1,
                    heightFactor: heightFactor,
                    child: child,
                  ),
          ),
        ],
      ),
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      isScrollControlled: true,
      modalBarrierColor: barrierColor,
      barrierLabel: localizations.scrimLabel,
      barrierOnTapHint: localizations.scrimOnTapHint(
        localizations.bottomSheetLabel,
      ),
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      showDragHandle: false,
      useSafeArea: useSafeArea,
      sheetAnimationStyle: sheetAnimationStyle,
    );
  }
}
