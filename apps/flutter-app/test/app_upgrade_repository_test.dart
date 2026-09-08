import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_models.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_repository.dart';

void main() {
  test(
    'the public API payload drives the mandatory decision, minimum and store destination end to end',
    () async {
      final dio = Dio();
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                data: <String, Object?>{
                  'success': true,
                  'data': <String, Object?>{
                    'upgrade_prompt': <String, Object?>{
                      'latest_version': '1.0.2',
                      'min_version': '1.0.1',
                      'force_update': true,
                      'title': 'Update available',
                      'message': 'A new version is available.',
                      'forced_message': 'Update to continue.',
                      'store_url': 'https://apps.apple.com/app/id6793017224',
                    },
                  },
                },
              ),
            );
          },
        ),
      );
      final config = await HttpAppUpgradeRepository(dio).loadConfig();
      final decision = AppUpgradePolicy.evaluate(
        currentVersion: '1.0.0',
        config: config,
      );
      expect(decision.forceUpdate, isTrue);
      expect(decision.message, 'Update to continue.');
      expect(decision.storeUrl, 'https://apps.apple.com/app/id6793017224');
      expect(
        AppUpgradePolicy.evaluate(
          currentVersion: '1.0.1',
          config: config,
        ).forceUpdate,
        isFalse,
      );
    },
  );

  test(
    'network failures remain failures because unavailable version rules must not grant permission to use the app',
    () async {
      final dio = Dio();
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.connectionTimeout,
              ),
            );
          },
        ),
      );
      await expectLater(
        HttpAppUpgradeRepository(dio).loadConfig(),
        throwsA(isA<DioException>()),
      );
    },
  );

  for (final body in [
    null,
    <String, Object?>{},
    {'success': false, 'data': <String, Object?>{}},
    {'success': true, 'data': <String, Object?>{}},
    {
      'success': true,
      'data': <String, Object?>{'upgrade_prompt': []},
    },
    {
      'success': true,
      'data': <String, Object?>{
        'upgrade_prompt': <String, Object?>{
          'force_update': 'true',
          'latest_version': '1.0.1',
        },
      },
    },
  ]) {
    test(
      'invalid response $body cannot silently disable a mandatory rule',
      () async {
        final dio = Dio();
        addTearDown(dio.close);
        dio.interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              handler.resolve(Response(requestOptions: options, data: body));
            },
          ),
        );
        await expectLater(
          HttpAppUpgradeRepository(dio).loadConfig(),
          throwsFormatException,
        );
      },
    );
  }

  test(
    'the Android repository requests Google rules and accepts an explicitly disabled prompt',
    () async {
      final dio = Dio();
      addTearDown(dio.close);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.queryParameters, {'platform': 'google'});
            handler.resolve(
              Response(
                requestOptions: options,
                data: <String, Object?>{
                  'success': true,
                  'data': <String, Object?>{'upgrade_prompt': null},
                },
              ),
            );
          },
        ),
      );
      expect(
        (await HttpAppUpgradeRepository(
          dio,
          platform: 'google',
        ).loadConfig()).upgradePrompt,
        isNull,
      );
    },
  );
}
