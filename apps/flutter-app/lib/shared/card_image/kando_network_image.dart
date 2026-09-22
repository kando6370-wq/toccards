import 'dart:async';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../api/app_http_transport.dart';

ImageProvider<Object> createKandoNetworkImage(
  String url, {
  Dio? dio,
  double scale = 1,
  Map<String, String>? headers,
  WebHtmlElementStrategy webHtmlElementStrategy = WebHtmlElementStrategy.never,
}) {
  if (!supportsNativeAppHttpTransport) {
    return NetworkImage(
      url,
      scale: scale,
      headers: headers,
      webHtmlElementStrategy: webHtmlElementStrategy,
    );
  }
  if (dio == null) {
    throw StateError('Native card images require the application image Dio.');
  }
  return KandoNetworkImage(url, dio: dio, scale: scale, headers: headers);
}

@immutable
class KandoNetworkImage extends ImageProvider<KandoNetworkImage> {
  const KandoNetworkImage(
    this.url, {
    required this.dio,
    this.scale = 1,
    this.headers,
  });

  final String url;
  final Dio dio;
  final double scale;
  final Map<String, String>? headers;

  @override
  Future<KandoNetworkImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<KandoNetworkImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    KandoNetworkImage key,
    ImageDecoderCallback decode,
  ) {
    final chunkEvents = StreamController<ImageChunkEvent>();
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, chunkEvents, decode),
      chunkEvents: chunkEvents.stream,
      scale: key.scale,
      debugLabel: key.url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<KandoNetworkImage>('Image key', key),
      ],
    );
  }

  Future<ui.Codec> _loadAsync(
    KandoNetworkImage key,
    StreamController<ImageChunkEvent> chunkEvents,
    ImageDecoderCallback decode,
  ) async {
    assert(key == this);
    final resolved = Uri.base.resolve(key.url);
    try {
      final response = await key.dio.get<List<int>>(
        resolved.toString(),
        options: Options(
          headers: key.headers,
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
        ),
        onReceiveProgress: (received, total) {
          chunkEvents.add(
            ImageChunkEvent(
              cumulativeBytesLoaded: received,
              expectedTotalBytes: total > 0 ? total : null,
            ),
          );
        },
      );
      final statusCode = response.statusCode ?? 0;
      if (statusCode != 200) {
        throw NetworkImageLoadException(statusCode: statusCode, uri: resolved);
      }

      final data = response.data;
      final bytes = data is Uint8List
          ? data
          : Uint8List.fromList(data ?? const <int>[]);
      if (bytes.isEmpty) {
        throw StateError('Network image is an empty file: $resolved');
      }
      return decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    } catch (_) {
      scheduleMicrotask(() {
        PaintingBinding.instance.imageCache.evict(key);
      });
      rethrow;
    } finally {
      unawaited(chunkEvents.close());
    }
  }

  @override
  bool operator ==(Object other) {
    return other is KandoNetworkImage &&
        other.url == url &&
        other.scale == scale &&
        identical(other.dio, dio) &&
        mapEquals(other.headers, headers);
  }

  @override
  int get hashCode => Object.hash(
    url,
    scale,
    identityHashCode(dio),
    headers == null
        ? null
        : Object.hashAllUnordered(
            headers!.entries.map(
              (entry) => Object.hash(entry.key, entry.value),
            ),
          ),
  );

  @override
  String toString() {
    return '${objectRuntimeType(this, 'KandoNetworkImage')}'
        '("$url", scale: ${scale.toStringAsFixed(1)}, headers: $headers)';
  }
}
