import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/shared/scan/scan_api_client.dart';

void main() {
  test(
    'recognizeImage uploads bytes with the session token because scans must be attributable in Admin',
    () async {
      final adapter = _RecordingAdapter((request) {
        expect(request.method, 'POST');
        expect(request.path, '/scan/recognize');
        expect(request.authorization, 'Bearer access-token');
        expect(request.formFields['platform'], 'iOS');
        expect(request.formFields['app_version'], '1.0.0');
        expect(request.fileName, 'scan.jpg');
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
                    'card_ref': '11958',
                    'name': 'Bushi Tenderfoot',
                    'set_code': 'CHK',
                    'card_number': '1',
                    'confidence': 86.2,
                  },
                ],
              },
            ],
          },
        });
      });

      final result = await ScanApiClient(_dio(adapter)).recognizeImage(
        _session,
        imageBytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'scan.jpg',
        platform: 'iOS',
        appVersion: '1.0.0',
      );

      expect(result.scanId, 'scan-1');
      expect(result.recognitionStatus, 'success');
      expect(result.results.single.candidates.single.cardRef, '11958');
      expect(result.results.single.candidates.single.name, 'Bushi Tenderfoot');
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
    final fields = <String, String>{};
    String? fileName;
    if (data is FormData) {
      for (final entry in data.fields) {
        fields[entry.key] = entry.value;
      }
      fileName = data.files.single.value.filename;
    }

    return handler(
      _RecordedRequest(
        method: options.method,
        path: options.path,
        authorization: options.headers['Authorization']?.toString(),
        formFields: fields,
        fileName: fileName,
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
    required this.formFields,
    required this.fileName,
    required this.body,
  });

  final String method;
  final String path;
  final String? authorization;
  final Map<String, String> formFields;
  final String? fileName;
  final Object? body;
}
