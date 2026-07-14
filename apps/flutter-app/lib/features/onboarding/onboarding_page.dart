import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kando_app/shared/ui/kando_style.dart';

import '../auth/auth_controller.dart';
import '../auth/ui/auth_sheet.dart';
import 'onboarding_controller.dart';
import 'onboarding_repository.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _pageController = PageController();
  var _currentIndex = 0;
  var _showSplash = true;
  var _showEntry = false;

  @override
  void initState() {
    super.initState();
    unawaited(_finishSplash());
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingControllerProvider);
    final slides = state.slides;

    if (slides.isEmpty) {
      return _OnboardingEntry(
        onAuthenticate: _authenticate,
        onContinueAsGuest: _complete,
      );
    }

    if (_showSplash) {
      return const _OnboardingSplash();
    }

    if (_showEntry) {
      return _OnboardingEntry(
        onAuthenticate: _authenticate,
        onContinueAsGuest: _complete,
      );
    }

    final isLast = _currentIndex == slides.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: KandoColors.mutedText,
                  ),
                  onPressed: () => setState(() => _showEntry = true),
                  child: const Text('Skip'),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: slides.length,
                  onPageChanged: (index) {
                    setState(() => _currentIndex = index);
                  },
                  itemBuilder: (context, index) {
                    return _OnboardingSlideView(
                      key: ValueKey('onboarding-guide-$index'),
                      index: index,
                      slide: slides[index],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var index = 0; index < slides.length; index += 1)
                    _PageDot(active: index == _currentIndex),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: const StadiumBorder(),
                  backgroundColor: KandoColors.accent,
                  foregroundColor: KandoColors.ink,
                  textStyle: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: isLast
                    ? () => setState(() => _showEntry = true)
                    : _next,
                child: Text(isLast ? 'Get Started' : 'Next'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _finishSplash() async {
    try {
      await Future.wait([
        Future<void>.delayed(const Duration(milliseconds: 1200)),
        ref.read(authControllerProvider.notifier).startupComplete,
      ]);
    } on Exception {
      // Auth owns its failure state; onboarding must not remain stuck on splash.
    }
    if (mounted) {
      setState(() => _showSplash = false);
    }
  }

  Future<void> _authenticate() async {
    await showAuthSheet(context);
    if (!mounted) return;
    if (ref.read(authControllerProvider).session?.isUser ?? false) {
      _complete();
    }
  }

  void _next() {
    _pageController.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _complete() {
    ref.read(onboardingControllerProvider.notifier).complete();
  }
}

class _OnboardingSplash extends StatelessWidget {
  const _OnboardingSplash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('onboarding-splash'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: KandoColors.accent,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: const Icon(
                  Icons.style_rounded,
                  size: 48,
                  color: KandoColors.ink,
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'KANDO',
                style: TextStyle(
                  color: KandoColors.text,
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
              const Spacer(),
              const LinearProgressIndicator(
                minHeight: 3,
                color: KandoColors.accent,
                backgroundColor: KandoColors.elevatedSurface,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingEntry extends StatelessWidget {
  const _OnboardingEntry({
    required this.onAuthenticate,
    required this.onContinueAsGuest,
  });

  final VoidCallback onAuthenticate;
  final VoidCallback onContinueAsGuest;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('onboarding-entry'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 32, 20, 20),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: KandoColors.elevatedSurface,
                  border: Border.all(color: KandoColors.border),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(
                  Icons.collections_bookmark_rounded,
                  size: 58,
                  color: KandoColors.accent,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Build your collection',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: KandoColors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Sign in to keep your cards connected across devices, or start now as a guest.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: KandoColors.mutedText,
                  fontSize: 16,
                  height: 1.45,
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: onAuthenticate,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  backgroundColor: KandoColors.accent,
                  foregroundColor: KandoColors.ink,
                  shape: const StadiumBorder(),
                ),
                child: const Text('Sign in or create account'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: onContinueAsGuest,
                style: TextButton.styleFrom(
                  foregroundColor: KandoColors.mutedText,
                  minimumSize: const Size.fromHeight(44),
                ),
                child: const Text('Skip and start now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingSlideView extends StatelessWidget {
  const _OnboardingSlideView({
    required this.index,
    required this.slide,
    super.key,
  });

  final int index;
  final OnboardingSlide slide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final imageHeight = (constraints.maxHeight * 0.48).clamp(144.0, 280.0);

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: imageHeight,
              width: double.infinity,
              child: _OnboardingImage(index: index, imageUrl: slide.imageUrl),
            ),
            const SizedBox(height: 24),
            Text(
              slide.title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              slide.body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        );
      },
    );
  }
}

class _OnboardingImage extends StatelessWidget {
  const _OnboardingImage({required this.index, required this.imageUrl});

  final int index;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        key: ValueKey('onboarding-image-$index'),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
        ),
        child: _isRemoteUrl(imageUrl)
            ? Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return const _ImageFallback();
                },
              )
            : const _ImageFallback(),
      ),
    );
  }

  bool _isRemoteUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.style_outlined,
        size: 96,
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    );
  }
}

class _PageDot extends StatelessWidget {
  const _PageDot({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: active ? 20 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outlineVariant,
        borderRadius: BorderRadius.circular(8),
      ),
    );
  }
}
