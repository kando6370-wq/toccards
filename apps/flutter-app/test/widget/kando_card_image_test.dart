import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/card_image/kando_card_image.dart';
import 'package:kando_app/shared/card_image/kando_network_image.dart';

void main() {
  testWidgets(
    'stalled native art releases its request so queued images can continue',
    (tester) async {
      final adapter = _StalledImageAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      await tester.pumpWidget(
        MaterialApp(
          home: Image(
            image: KandoNetworkImage(
              'https://img.example/stalled.png',
              dio: dio,
            ),
            errorBuilder: (_, _, _) => const Text('Image unavailable'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(cardImageRequestDeadline);
      await tester.pump();
      expect(adapter.cancelled, isTrue);
      expect(find.text('Image unavailable'), findsOneWidget);
    },
  );

  test(
    'display pixels select shared list decoding without limiting large previews',
    () async {
      expect(
        cardImageDecodeSize(const Size(125, 174), 3),
        cardImagePreloadSize,
      );
      expect(cardImageDecodeSize(const Size(42, 58), 3), cardImagePreloadSize);
      expect(
        cardImageDecodeSize(const Size(300, 420), 3),
        const Size(1024, 1536),
      );
      expect(cardImageDecodeSize(const Size(double.infinity, 200), 3), isNull);
      final dio = Dio();
      final list = KandoNetworkImage(
        'https://img.example/card.png',
        dio: dio,
        decodeSize: cardImagePreloadSize,
      );
      final preload = KandoNetworkImage(
        'https://img.example/card.png',
        dio: dio,
        decodeSize: cardImagePreloadSize,
      );
      final preview = KandoNetworkImage(
        'https://img.example/card.png',
        dio: dio,
      );
      expect(
        await list.obtainKey(ImageConfiguration.empty),
        await preload.obtainKey(ImageConfiguration.empty),
      );
      expect(
        list,
        isNot(preview),
        reason: 'full artwork must not reuse a lower resolution decode',
      );
    },
  );

  testWidgets(
    'sized native decoding reduces pixels and leaves artwork proportions intact',
    (tester) async {
      late Uint8List bytes;
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 1400, 2000),
          Paint()..color = Colors.green,
        );
        final picture = recorder.endRecording();
        final original = await picture.toImage(1400, 2000);
        bytes = (await original.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        original.dispose();
        picture.dispose();
      });
      final adapter = _ImageAdapter(bytes: bytes);
      final dio = Dio()..httpClientAdapter = adapter;
      final provider = KandoNetworkImage(
        'https://img.example/large-card.png',
        dio: dio,
        decodeSize: cardImagePreloadSize,
      );
      late ImageInfo decoded;
      await tester.runAsync(() async {
        final result = Completer<ImageInfo>();
        final stream = provider.resolve(ImageConfiguration.empty);
        final listener = ImageStreamListener(
          (image, _) => result.complete(image),
        );
        stream.addListener(listener);
        decoded = await result.future;
        stream.removeListener(listener);
      });
      expect(decoded.image.width, 538);
      expect(decoded.image.height, 768);
      expect(
        decoded.image.width / decoded.image.height,
        closeTo(1400 / 2000, 0.002),
      );
      expect(
        decoded.image.width * decoded.image.height,
        lessThan(1400 * 2000 / 4),
      );
      decoded.dispose();
      late ImageInfo preview;
      await tester.runAsync(() async {
        final result = Completer<ImageInfo>();
        final stream = KandoNetworkImage(
          'https://img.example/large-card.png',
          dio: dio,
        ).resolve(ImageConfiguration.empty);
        final listener = ImageStreamListener(
          (image, _) => result.complete(image),
        );
        stream.addListener(listener);
        preview = await result.future;
        stream.removeListener(listener);
      });
      expect(preview.image.width, 1400);
      expect(preview.image.height, 2000);
      preview.dispose();
    },
  );

  test(
    'an asynchronous decode failure evicts the provider key so card art can retry',
    () async {
      final imageCache = PaintingBinding.instance.imageCache;
      imageCache.clear();
      imageCache.clearLiveImages();
      final dio = Dio()..httpClientAdapter = _ImageAdapter();
      final provider = KandoNetworkImage(
        'https://img.example/retry-card.png',
        dio: dio,
      );
      final key = await provider.obtainKey(ImageConfiguration.empty);
      final cachedImage = Completer<ImageInfo>();
      imageCache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(cachedImage.future),
      );
      expect(imageCache.statusForKey(key).pending, isTrue);

      final decodeFailed = Completer<void>();
      final stream = provider.loadImage(
        key,
        (buffer, {getTargetSize}) async {
          buffer.dispose();
          await Future<void>.delayed(Duration.zero);
          throw StateError('asynchronous decode failed');
        },
      );
      final listener = ImageStreamListener(
        (_, _) {},
        onError: (_, _) {
          if (!decodeFailed.isCompleted) decodeFailed.complete();
        },
      );
      stream.addListener(listener);
      await decodeFailed.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(Duration.zero);
      stream.removeListener(listener);

      expect(imageCache.statusForKey(key).untracked, isTrue);
      var retried = false;
      imageCache.putIfAbsent(key, () {
        retried = true;
        return OneFrameImageStreamCompleter(Completer<ImageInfo>().future);
      });
      expect(retried, isTrue);
      imageCache.evict(key);
    },
  );

  testWidgets(
    'card image keeps its display box when decode sizing is enabled',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(
              width: 125,
              height: 174,
              child: KandoCardImage(
                imageUrl: 'https://invalid.test/layout.png',
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(KandoCardImage)), const Size(125, 174));
      expect(tester.getSize(find.byType(Image).first), const Size(125, 174));
    },
  );

  testWidgets('missing card art uses the global Figma placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: KandoCardImage(imageUrl: null)),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, const AssetImage('assets/home/trend_placeholder.png'));
  });

  testWidgets('failed card art uses the same global Figma placeholder', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: KandoCardImage(imageUrl: 'https://invalid.test/card.png'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image ==
                const AssetImage('assets/home/trend_placeholder.png'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('native card art provider uses its shared Dio', (tester) async {
    final adapter = _ImageAdapter();
    final dio = Dio()..httpClientAdapter = adapter;

    await tester.pumpWidget(
      MaterialApp(
        home: Image(
          image: KandoNetworkImage('https://img.example/card.png', dio: dio),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.image, isA<KandoNetworkImage>());
    expect((image.image as KandoNetworkImage).dio, same(dio));
    expect(adapter.requestedUrls, ['https://img.example/card.png']);
  });
}

class _StalledImageAdapter implements HttpClientAdapter {
  var cancelled = false;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final response = Completer<ResponseBody>();
    cancelFuture?.then((_) {
      cancelled = true;
      response.completeError(
        DioException(requestOptions: options, type: DioExceptionType.cancel),
      );
    });
    return response.future;
  }

  @override
  void close({bool force = false}) {}
}

class _ImageAdapter implements HttpClientAdapter {
  _ImageAdapter({Uint8List? bytes}) : bytes = bytes ?? _pixel;

  final Uint8List bytes;
  static final _pixel = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  final requestedUrls = <String>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestedUrls.add(options.uri.toString());
    return ResponseBody.fromBytes(
      bytes,
      200,
      headers: {
        Headers.contentTypeHeader: ['image/png'],
        Headers.contentLengthHeader: ['${bytes.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
