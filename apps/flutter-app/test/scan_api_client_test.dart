import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/shared/scan/scan_api_client.dart';
import 'package:kando_app/shared/scan/scan_image_hasher.dart';

void main() {
  test(
    'recognizeImage sends hashes plus only the corrected crop to our API because the external recognizer must never receive an image',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'POST');
        expect(request.path, '/scan/recognize');
        expect(request.authorization, 'Bearer access-token');
        final form = request.body as FormData;
        expect(Map<String, String>.fromEntries(form.fields), {
          'r': _hash,
          'g': _hash,
          'b': _hash,
          'filename': 'scan.jpg',
          'platform': 'iOS',
          'app_version': '1.0.0',
        });
        expect(form.files, hasLength(1));
        expect(form.files.single.key, 'image');
        expect(form.files.single.value.filename, 'scan-card.jpg');
        expect(form.files.single.value.length, 4);
        expect(form.files.single.value.contentType.toString(), 'image/jpeg');
        return _json(200, {
          'success': true,
          'data': {
            'scan_id': 'scan-1',
            'recognition_status': 'success',
            'results': [
              {
                'index': 1,
                'matched': true,
                'candidates': [
                  {
                    'card_ref': '10738',
                    'name': 'Bushi Tenderfoot',
                    'set_code': 'CHK',
                    'card_number': '1',
                    'confidence': 80.99,
                  },
                  {
                    'card_ref': '240872',
                    'name': 'Devoted Retainer',
                    'set_code': 'CHK',
                    'card_number': '2',
                    'confidence': 80.729,
                  },
                ],
              },
            ],
          },
        });
      });

      final result = await ScanApiClient(_dio(adapter)).recognizeImage(
        _session,
        hashes: ScanImageHashes(
          r: _hash,
          g: _hash,
          b: _hash,
          cardImageBytes: Uint8List.fromList([1, 2, 3, 4]),
        ),
        fileName: 'scan.jpg',
        platform: 'iOS',
        appVersion: '1.0.0',
      );

      expect(result.scanId, 'scan-1');
      expect(result.recognitionStatus, 'success');
      expect(result.results.single.candidates.first.cardRef, '10738');
      expect(result.results.single.candidates.first.confidence, 80.99);
      expect(result.results.single.candidates.last.cardRef, '240872');
      expect(result.results.single.candidates.last.confidence, 80.729);
    },
  );

  test(
    'recognition rejects confidence outside 0 to 100 because pHash similarity is neither a probability nor a client-calibrated value',
    () async {
      final adapter = _RecordingAdapter((_) => _json(200, {
        'success': true,
        'data': {
          'scan_id': 'scan-1',
          'recognition_status': 'success',
          'results': [
            {
              'index': 1,
              'matched': true,
              'candidates': [
                {
                  'card_ref': '10738',
                  'name': 'Bushi Tenderfoot',
                  'confidence': 101,
                },
              ],
            },
          ],
        },
      }));

      await expectLater(
        ScanApiClient(_dio(adapter)).recognizeImage(
          _session,
          hashes: ScanImageHashes(
            r: _hash,
            g: _hash,
            b: _hash,
            cardImageBytes: Uint8List.fromList([1, 2, 3, 4]),
          ),
          fileName: 'scan.jpg',
          platform: 'iOS',
          appVersion: '1.0.0',
        ),
        throwsA(isA<ScanApiException>()),
      );
    },
  );

  test(
    'confirmMatch persists the reviewed candidate because Added state requires a server item id',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'POST');
        expect(request.path, '/scan/scan-1/confirm');
        expect(request.authorization, 'Bearer access-token');
        expect(request.body, {
          'folder_id': 'main',
          'card_ref': '11958',
          'quantity': 2,
          'grader': 'PSA',
          'condition': null,
          'grade': 10.0,
          'language': 'Japanese',
          'finish': 'Foil',
          'purchase_price': 12.5,
          'purchase_currency': 'USD',
          'notes': 'reviewed scan',
        });
        return _json(201, {
          'success': true,
          'data': {
            'scan_id': 'scan-1',
            'collection_item_id': 'item-1',
            'card_ref': '11958',
            'folder_id': 'main',
          },
        });
      });

      final result = await ScanApiClient(_dio(adapter)).confirmMatch(
        _session,
        scanId: 'scan-1',
        item: const ScanCollectionItemInput(
          folderId: 'main',
          cardRef: '11958',
          quantity: 2,
          grader: 'PSA',
          condition: null,
          grade: 10,
          language: 'Japanese',
          finish: 'Foil',
          purchasePrice: 12.5,
          purchaseCurrency: 'USD',
          notes: 'reviewed scan',
        ),
      );

      expect(result.collectionItemId, 'item-1');
    },
  );
}

const _session = AuthSession(
  ownerType: OwnerType.anonymous,
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
  anonymousId: 'anon-1',
);

const _hash = 'vgM8KW2_mtY4LMLQZJvFpzl823zE3mx0mWhpCcRYaGw';

Dio _dio(_RecordingAdapter adapter) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test/api/v1'));
  dio.httpClientAdapter = adapter;
  return dio;
}

ResponseBody _json(int statusCode, Map<String, Object?> body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.handler);

  final ResponseBody Function(_RecordedRequest request) handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = options.data;
    return handler(
      _RecordedRequest(
        method: options.method,
        path: options.path,
        authorization: options.headers['Authorization']?.toString(),
        body: data,
      ),
    );
  }

  @override
  void close({bool force = false}) {}
}

class _RecordedRequest {
  const _RecordedRequest({
    required this.method,
    required this.path,
    required this.authorization,
    required this.body,
  });

  final String method;
  final String path;
  final String? authorization;
  final Object? body;
}
