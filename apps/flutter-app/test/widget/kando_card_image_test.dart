import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/card_image/kando_card_image.dart';
import 'package:kando_app/shared/card_image/kando_network_image.dart';

void main() {
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

class _ImageAdapter implements HttpClientAdapter {
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
      _pixel,
      200,
      headers: {
        Headers.contentTypeHeader: ['image/png'],
        Headers.contentLengthHeader: ['${_pixel.length}'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
