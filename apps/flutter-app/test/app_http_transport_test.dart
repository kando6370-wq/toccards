import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_repository.dart';
import 'package:kando_app/features/auth/auth_controller.dart';
import 'package:kando_app/shared/analytics/mixpanel_bootstrap.dart';
import 'package:kando_app/shared/api/app_http_transport.dart';
import 'package:kando_app/shared/attribution/singular_bootstrap.dart';
import 'package:kando_app/shared/card_data/card_data_providers.dart';
import 'package:kando_app/shared/currency/currency_rate_api.dart';
import 'package:kando_app/shared/portfolio/portfolio_providers.dart';
import 'package:kando_app/shared/scan/scan_api_client.dart';
import 'package:kando_app/shared/scan/scan_providers.dart';

void main() {
  test('transport mode accepts only native and IO build values', () {
    expect(parseAppHttpTransportMode('native'), AppHttpTransportMode.native);
    expect(parseAppHttpTransportMode('io'), AppHttpTransportMode.io);
    expect(
      () => parseAppHttpTransportMode('other'),
      throwsA(isA<StateError>()),
    );
  });

  test('all business Dio clients share one application transport', () {
    final adapter = _RecordingAdapter();
    final transport = AppHttpTransport(
      mode: AppHttpTransportMode.native,
      adapter: adapter,
    );
    final container = ProviderContainer(
      overrides: [
        appHttpTransportProvider.overrideWith((ref) {
          ref.onDispose(transport.close);
          return transport;
        }),
      ],
    );

    final clients = <Dio>[
      container.read(authDioProvider),
      container.read(cardDataDioProvider),
      container.read(portfolioDioProvider),
      container.read(scanDioProvider),
      container.read(appUpgradeDioProvider),
      container.read(currencyRateDioProvider),
      container.read(appImageDioProvider),
      createMixpanelDio(transport: transport),
      createSingularDio(transport: transport),
    ];

    for (final client in clients) {
      expect(client.httpClientAdapter, same(adapter));
    }
    expect(container.read(scanDioProvider).options.connectTimeout, isNull);

    container.dispose();
    expect(adapter.closeCalls, 1);
    expect(adapter.lastForce, isTrue);
  });

  test('scan keeps the legacy connect timeout only on IO transport', () {
    final nativeAdapter = _RecordingAdapter();
    final native = AppHttpTransport(
      mode: AppHttpTransportMode.native,
      adapter: nativeAdapter,
    );
    final ioAdapter = _RecordingAdapter();
    final io = AppHttpTransport(
      mode: AppHttpTransportMode.io,
      adapter: ioAdapter,
    );
    addTearDown(native.close);
    addTearDown(io.close);

    expect(createScanDio(transport: native).options.connectTimeout, isNull);
    expect(
      createScanDio(transport: io).options.connectTimeout,
      const Duration(seconds: 10),
    );
    expect(scanRequestDeadline, const Duration(seconds: 25));
  });

  test('native mode stays on Dio IO outside iOS and Android', () {
    if (Platform.isIOS || Platform.isAndroid) return;
    final transport = AppHttpTransport(mode: AppHttpTransportMode.native);
    addTearDown(transport.close);

    expect(transport.adapter, isA<IOHttpClientAdapter>());
  });
}

class _RecordingAdapter implements HttpClientAdapter {
  var closeCalls = 0;
  bool? lastForce;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    throw UnimplementedError();
  }

  @override
  void close({bool force = false}) {
    closeCalls++;
    lastForce = force;
  }
}
