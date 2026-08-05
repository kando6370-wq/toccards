import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/shared/ui/kando_style.dart';
import 'package:video_player/video_player.dart';

import '../auth/auth_controller.dart';
import '../auth/ui/auth_sheet.dart';
import '../../shared/analytics/analytics_events.dart';
import '../../shared/analytics/app_analytics.dart';
import 'onboarding_controller.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  static const _slides = [
    _OnboardingSlide(
      title: 'Instantly Scan Cards',
      description:
          'Identify your cards with AI and add\nthem to your collection in seconds.',
      mediaAsset: 'assets/onboarding/guide_scan.mp4',
      placeholderAsset: 'assets/onboarding/guide_scan_placeholder.png',
      primaryLabel: "LET'S START",
    ),
    _OnboardingSlide(
      title: 'Track Card Values',
      description:
          'Follow market prices, trends, and value\nchanges for the cards you care about.',
      mediaAsset: 'assets/onboarding/guide_values.mp4',
      placeholderAsset: 'assets/onboarding/guide_values_placeholder.png',
      primaryLabel: 'NEXT',
    ),
    _OnboardingSlide(
      title: 'Personalized Wishlist',
      description: 'Save the cards you want and never lose track',
      mediaAsset: 'assets/onboarding/guide_wishlist.mp4',
      placeholderAsset: 'assets/onboarding/guide_wishlist_placeholder.png',
      primaryLabel: 'SIGN UP/SIGN IN',
    ),
  ];

  final _pageController = PageController();
  late final List<_OnboardingVideoController> _videoControllers;
  var _currentIndex = 0;
  var _lastTrackedGuideIndex = 0;
  var _isPageTransitioning = false;
  bool? _reduceMotion;

  @override
  void initState() {
    super.initState();
    ref.read(analyticsProvider).track(AnalyticsEvent.guide1View);
    _videoControllers = [
      for (final slide in _slides) _OnboardingVideoController(slide.mediaAsset),
    ];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (!reduceMotion) _preloadVideosFrom(_currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in _videoControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('onboarding-guides'),
      backgroundColor: const Color(0xFF0D0F08),
      body: NotificationListener<ScrollNotification>(
        onNotification: _handlePageScroll,
        child: PageView.builder(
          key: const ValueKey('onboarding-page-view'),
          controller: _pageController,
          itemCount: _slides.length,
          onPageChanged: _handlePageChanged,
          itemBuilder: (context, index) {
            final isLast = index == _slides.length - 1;
            return _OnboardingSlideView(
              key: ValueKey('onboarding-guide-$index'),
              index: index,
              slide: _slides[index],
              isActive: index == _currentIndex && !_isPageTransitioning,
              videoController: _videoControllers[index],
              currentIndex: _currentIndex,
              pageCount: _slides.length,
              onPrimaryPressed: isLast ? _authenticate : _next,
              onContinueAsGuest: isLast ? _complete : null,
            );
          },
        ),
      ),
    );
  }

  bool _handlePageScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      _setPageTransitioning(true);
    } else if (notification is ScrollEndNotification) {
      _setPageTransitioning(false);
    }
    return false;
  }

  void _handlePageChanged(int index) {
    setState(() => _currentIndex = index);
    if (_lastTrackedGuideIndex == index) return;
    _lastTrackedGuideIndex = index;
    final event = switch (index) {
      0 => AnalyticsEvent.guide1View,
      1 => AnalyticsEvent.guide2View,
      _ => AnalyticsEvent.guide3View,
    };
    ref.read(analyticsProvider).track(event);
    if (_reduceMotion != true) _preloadVideosFrom(index);
  }

  void _preloadVideosFrom(int index) {
    final lastIndex = (index + 1).clamp(0, _videoControllers.length - 1);
    for (
      var preloadIndex = index;
      preloadIndex <= lastIndex;
      preloadIndex += 1
    ) {
      final controller = _videoControllers[preloadIndex];
      unawaited(controller.initialize());
    }
  }

  void _setPageTransitioning(bool value) {
    if (_isPageTransitioning == value) return;
    setState(() => _isPageTransitioning = value);
  }

  Future<void> _authenticate() async {
    await showAuthSheet(context);
    if (!mounted) return;
    if (ref.read(authControllerProvider).session?.isUser ?? false) {
      await ref.read(onboardingControllerProvider.notifier).complete();
    }
  }

  void _next() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _complete() {
    ref.read(analyticsProvider).track(AnalyticsEvent.signSkipClick);
    ref.read(onboardingControllerProvider.notifier).complete();
  }
}

class _OnboardingSlide {
  const _OnboardingSlide({
    required this.title,
    required this.description,
    required this.mediaAsset,
    required this.placeholderAsset,
    required this.primaryLabel,
  });

  final String title;
  final String description;
  final String mediaAsset;
  final String placeholderAsset;
  final String primaryLabel;
}

class _OnboardingSlideView extends StatelessWidget {
  const _OnboardingSlideView({
    required this.index,
    required this.slide,
    required this.isActive,
    required this.videoController,
    required this.currentIndex,
    required this.pageCount,
    required this.onPrimaryPressed,
    required this.onContinueAsGuest,
    super.key,
  });

  final int index;
  final _OnboardingSlide slide;
  final bool isActive;
  final _OnboardingVideoController videoController;
  final int currentIndex;
  final int pageCount;
  final VoidCallback onPrimaryPressed;
  final VoidCallback? onContinueAsGuest;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 360;
        final panelHeight = isCompact ? 360.0 : 328.0;
        final horizontalPadding = isCompact ? 16.0 : 21.0;
        final controlInset = isCompact ? 2.0 : 32.0;
        final safeBottom = MediaQuery.paddingOf(context).bottom;
        final bottomPadding = safeBottom > 34 ? safeBottom + 14 : 48.0;

        return Stack(
          fit: StackFit.expand,
          children: [
            _OnboardingMedia(
              key: ValueKey('onboarding-media-placeholder-$index'),
              index: index,
              placeholderAsset: slide.placeholderAsset,
              isActive: isActive,
              videoController: videoController,
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: RepaintBoundary(
                child: Container(
                  height: panelHeight,
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    0,
                    horizontalPadding,
                    bottomPadding,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x000D0F08), Color(0xF20D0F08)],
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        slide.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: const Color(0xFFE3E3D6),
                          fontFamily: 'Fraunces',
                          fontSize: isCompact ? 28 : 32,
                          fontWeight: FontWeight.w400,
                          height: 40 / 32,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        slide.description,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: KandoColors.mutedText,
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          height: 24 / 16,
                        ),
                      ),
                      const SizedBox(height: 24),
                      _PageIndicator(
                        currentIndex: currentIndex,
                        pageCount: pageCount,
                      ),
                      const SizedBox(height: 24),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: controlInset),
                        child: _OnboardingButton(
                          tooltip: slide.primaryLabel,
                          label: slide.primaryLabel,
                          onPressed: onPrimaryPressed,
                          showArrow: true,
                        ),
                      ),
                      if (onContinueAsGuest != null) ...[
                        const SizedBox(height: 12),
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: controlInset,
                          ),
                          child: _OnboardingButton(
                            tooltip: 'Skip and start now',
                            label: 'SKIP AND START NOW',
                            onPressed: onContinueAsGuest!,
                            secondary: true,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OnboardingMedia extends StatelessWidget {
  const _OnboardingMedia({
    required this.index,
    required this.placeholderAsset,
    required this.isActive,
    required this.videoController,
    super.key,
  });

  final int index;
  final String placeholderAsset;
  final bool isActive;
  final _OnboardingVideoController videoController;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return LayoutBuilder(
      builder: (context, constraints) {
        final topInset = MediaQuery.paddingOf(context).top;
        final baseHeight = constraints.maxWidth * (516 / 390);
        final mediaHeight = (baseHeight + topInset).clamp(
          0.0,
          constraints.maxHeight,
        );

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: constraints.maxWidth,
            height: mediaHeight,
            child: RepaintBoundary(
              child: ClipRect(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      placeholderAsset,
                      key: ValueKey('onboarding-media-first-frame-$index'),
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      filterQuality: FilterQuality.high,
                      excludeFromSemantics: true,
                    ),
                    _LoopingOnboardingVideo(
                      key: ValueKey('onboarding-video-$index'),
                      videoController: videoController,
                      isActive: isActive,
                      enabled: !reduceMotion,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OnboardingVideoController extends ChangeNotifier {
  _OnboardingVideoController(this.asset);

  static const _initializationTimeout = Duration(seconds: 4);

  final String asset;
  VideoPlayerController? _controller;
  var _ready = false;
  var _failed = false;
  var _initializing = false;
  var _disposed = false;

  VideoPlayerController? get controller => _ready ? _controller : null;

  Future<void> initialize() async {
    if (_initializing || _ready || _failed || _disposed) return;
    _initializing = true;
    final controller = VideoPlayerController.asset(asset);
    _controller = controller;

    try {
      await controller.initialize().timeout(_initializationTimeout);
      if (_disposed || controller != _controller) {
        return;
      }
      await controller.setLooping(true);
      await controller.setVolume(0);
      controller.addListener(_handleControllerValue);
      _initializing = false;
      _ready = true;
      notifyListeners();
    } catch (_) {
      if (controller != _controller) return;
      _controller = null;
      _initializing = false;
      _failed = true;
      await controller.dispose();
      if (!_disposed) notifyListeners();
    }
  }

  void _handleControllerValue() {
    if (_ready && (_controller?.value.hasError ?? false)) {
      _fallbackToFirstFrame();
    }
  }

  void _fallbackToFirstFrame() {
    if (_failed || _disposed) return;
    _failed = true;
    _ready = false;
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_handleControllerValue);
    if (controller != null) unawaited(controller.dispose());
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_handleControllerValue);
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }
}

class _LoopingOnboardingVideo extends StatefulWidget {
  const _LoopingOnboardingVideo({
    required this.videoController,
    required this.isActive,
    required this.enabled,
    super.key,
  });

  final _OnboardingVideoController videoController;
  final bool isActive;
  final bool enabled;

  @override
  State<_LoopingOnboardingVideo> createState() =>
      _LoopingOnboardingVideoState();
}

class _LoopingOnboardingVideoState extends State<_LoopingOnboardingVideo>
    with WidgetsBindingObserver {
  AppLifecycleState? _lifecycleState;

  bool get _shouldPlay =>
      widget.enabled &&
      widget.isActive &&
      (_lifecycleState == null || _lifecycleState == AppLifecycleState.resumed);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.videoController.addListener(_handleVideoControllerChanged);
    _lifecycleState = WidgetsBinding.instance.lifecycleState;
    unawaited(_syncPlayback());
  }

  @override
  void didUpdateWidget(covariant _LoopingOnboardingVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.videoController != oldWidget.videoController) {
      oldWidget.videoController.removeListener(_handleVideoControllerChanged);
      widget.videoController.addListener(_handleVideoControllerChanged);
    }
    if (widget.videoController != oldWidget.videoController ||
        widget.enabled != oldWidget.enabled ||
        widget.isActive != oldWidget.isActive) {
      unawaited(_syncPlayback());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    unawaited(_syncPlayback());
  }

  void _handleVideoControllerChanged() {
    if (!mounted) return;
    setState(() {});
    unawaited(_syncPlayback());
  }

  Future<void> _syncPlayback() async {
    final controller = widget.videoController.controller;
    if (controller == null) return;
    try {
      if (_shouldPlay) {
        await controller.play();
      } else {
        await controller.pause();
      }
    } catch (_) {
      widget.videoController._fallbackToFirstFrame();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.videoController.removeListener(_handleVideoControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.videoController.controller;
    if (!widget.enabled || controller == null) return const SizedBox.shrink();
    final size = controller.value.size;

    return IgnorePointer(
      child: AnimatedOpacity(
        key: const ValueKey('onboarding-video-layer'),
        opacity: 1,
        duration: const Duration(milliseconds: 120),
        child: FittedBox(
          fit: BoxFit.cover,
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }
}

class _PageIndicator extends StatelessWidget {
  const _PageIndicator({required this.currentIndex, required this.pageCount});

  final int currentIndex;
  final int pageCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < pageCount; index += 1) ...[
          if (index > 0) const SizedBox(width: 8),
          AnimatedContainer(
            key: ValueKey('onboarding-page-indicator-$index'),
            duration: const Duration(milliseconds: 180),
            width: index == currentIndex ? 16 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: index == currentIndex
                  ? KandoColors.accent
                  : const Color(0xFF34362D),
              borderRadius: BorderRadius.circular(9999),
            ),
          ),
        ],
      ],
    );
  }
}

class _OnboardingButton extends StatelessWidget {
  const _OnboardingButton({
    required this.tooltip,
    required this.label,
    required this.onPressed,
    this.showArrow = false,
    this.secondary = false,
  });

  final String tooltip;
  final String label;
  final VoidCallback onPressed;
  final bool showArrow;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final foreground = secondary ? KandoColors.text : const Color(0xFF2F3300);

    return SizedBox(
      width: double.infinity,
      height: 44,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: Tooltip(
          message: tooltip,
          child: FilledButton(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
              backgroundColor: secondary
                  ? KandoColors.elevatedSurface
                  : KandoColors.accent,
              foregroundColor: foreground,
              shape: StadiumBorder(
                side: secondary
                    ? const BorderSide(color: KandoColors.borderSubtle)
                    : BorderSide.none,
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                height: 16 / 13,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label),
                if (showArrow) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward, size: 20),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
