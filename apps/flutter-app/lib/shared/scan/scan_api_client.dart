import 'dart:async';

import 'package:dio/dio.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/auth/auth_repository.dart';

import 'scan_image_hasher_contract.dart';

const scanApiBaseUrl = authApiBaseUrl;
const scanRequestDeadline = Duration(seconds: 15);
const scanRequestTimeoutCode = 'REQUEST_TIMEOUT';
const scanRequestTimeoutMessage = 'Request timed out. Please try again.';

Dio createScanDio({String baseUrl = scanApiBaseUrl}) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 4),
      receiveTimeout: const Duration(seconds: 12),
    ),
  );
}

class ScanApiException implements Exception {
  const ScanApiException(this.message, {this.code, this.quota});

  final String message;
  final String? code;
  final ScanQuotaDto? quota;

  @override
  String toString() => message;
}

class ScanRecognitionDto {
  const ScanRecognitionDto({
    required this.scanId,
    required this.recognitionStatus,
    required this.results,
    required this.quota,
  });

  final String scanId;
  final String recognitionStatus;
  final List<ScanResultDto> results;
  final ScanQuotaDto quota;

  factory ScanRecognitionDto.fromJson(Map<String, Object?> json) {
    return ScanRecognitionDto(
      scanId: _requiredString(json['scan_id']),
      recognitionStatus: _requiredString(json['recognition_status']),
      results: _items(json['results']).map(ScanResultDto.fromJson).toList(),
      quota: ScanQuotaDto.fromJson(_requiredMap(json['quota'])),
    );
  }
}

class ScanQuotaDto {
  const ScanQuotaDto({
    required this.limit,
    required this.reserved,
    required this.consumed,
    required this.remaining,
    required this.unlimited,
  });

  final int limit;
  final int reserved;
  final int consumed;
  final int remaining;
  final bool unlimited;

  factory ScanQuotaDto.fromJson(Map<String, Object?> json) {
    return ScanQuotaDto(
      limit: _requiredInt(json['limit']),
      reserved: _requiredInt(json['reserved']),
      consumed: _requiredInt(json['consumed']),
      remaining: _requiredInt(json['remaining']),
      unlimited: json['unlimited'] == true,
    );
  }
}

class ScanResultDto {
  const ScanResultDto({
    required this.index,
    required this.matched,
    required this.candidates,
  });

  final int index;
  final bool matched;
  final List<ScanCandidateDto> candidates;

  factory ScanResultDto.fromJson(Map<String, Object?> json) {
    return ScanResultDto(
      index: _requiredInt(json['index']),
      matched: json['matched'] == true,
      candidates: _items(
        json['candidates'],
      ).map(ScanCandidateDto.fromJson).toList(),
    );
  }
}

class ScanCandidateDto {
  const ScanCandidateDto({
    required this.cardRef,
    required this.name,
    required this.setCode,
    required this.cardNumber,
    required this.confidence,
  });

  final String cardRef;
  final String name;
  final String? setCode;
  final String? cardNumber;
  final double? confidence;

  factory ScanCandidateDto.fromJson(Map<String, Object?> json) {
    return ScanCandidateDto(
      cardRef: _requiredString(json['card_ref']),
      name: _requiredString(json['name']),
      setCode: _nullableString(json['set_code']),
      cardNumber: _nullableString(json['card_number']),
      confidence: _nullableConfidence(json['confidence']),
    );
  }
}

class ScanConfirmationDto {
  const ScanConfirmationDto({
    required this.scanId,
    required this.collectionItemId,
    required this.cardRef,
    required this.folderId,
  });

  final String scanId;
  final String collectionItemId;
  final String cardRef;
  final String folderId;

  factory ScanConfirmationDto.fromJson(Map<String, Object?> json) {
    return ScanConfirmationDto(
      scanId: _requiredString(json['scan_id']),
      collectionItemId: _requiredString(json['collection_item_id']),
      cardRef: _requiredString(json['card_ref']),
      folderId: _requiredString(json['folder_id']),
    );
  }
}

class ScanCollectionItemInput {
  const ScanCollectionItemInput({
    required this.folderId,
    required this.cardRef,
    required this.quantity,
    required this.grader,
    required this.condition,
    required this.grade,
    required this.language,
    required this.finish,
    required this.purchasePrice,
    required this.purchaseCurrency,
    required this.notes,
  });

  final String folderId;
  final String cardRef;
  final int quantity;
  final String grader;
  final String? condition;
  final double? grade;
  final String language;
  final String finish;
  final double? purchasePrice;
  final String? purchaseCurrency;
  final String? notes;

  Map<String, Object?> toJson() {
    return {
      'folder_id': folderId,
      'card_ref': cardRef,
      'quantity': quantity,
      'grader': grader,
      'condition': condition,
      'grade': grade,
      'language': language,
      'finish': finish,
      'purchase_price': purchasePrice,
      'purchase_currency': purchaseCurrency,
      'notes': notes,
    };
  }
}

abstract interface class ScanApi {
  Future<ScanQuotaDto> getQuota(
    AuthSession session, {
    bool localPremiumVerified = false,
  });
  Future<ScanRecognitionDto> recognizeImage(
    AuthSession session, {
    required ScanImageHashes hashes,
    required String fileName,
    required String platform,
    required String appVersion,
    required String requestId,
    bool localPremiumVerified = false,
    String? cardNumber,
    String? deviceModel,
    String? osVersion,
  });
  Future<ScanConfirmationDto> confirmMatch(
    AuthSession session, {
    required String scanId,
    required ScanCollectionItemInput item,
  });
}

class ScanApiClient implements ScanApi {
  const ScanApiClient(this._dio, {this.requestDeadline = scanRequestDeadline});

  final Dio _dio;
  final Duration requestDeadline;

  @override
  Future<ScanQuotaDto> getQuota(
    AuthSession session, {
    bool localPremiumVerified = false,
  }) async {
    final data = await _requestData(
      'GET',
      '/scan/quota',
      session,
      null,
      localPremiumVerified: localPremiumVerified,
    );
    return ScanQuotaDto.fromJson(data);
  }

  @override
  Future<ScanRecognitionDto> recognizeImage(
    AuthSession session, {
    required ScanImageHashes hashes,
    required String fileName,
    required String platform,
    required String appVersion,
    required String requestId,
    bool localPremiumVerified = false,
    String? cardNumber,
    String? deviceModel,
    String? osVersion,
  }) async {
    final cardImageBytes = hashes.cardImageBytes;
    if (cardImageBytes == null) {
      throw const ScanApiException('The corrected card image is unavailable.');
    }
    final body = FormData.fromMap(<String, Object?>{
      'r': hashes.r,
      'g': hashes.g,
      'b': hashes.b,
      'filename': fileName,
      'platform': platform,
      'app_version': appVersion,
      'request_id': requestId,
      if (cardNumber != null) 'card_number': cardNumber,
      if (deviceModel != null) 'device_model': deviceModel,
      if (osVersion != null) 'os_version': osVersion,
      'image': MultipartFile.fromBytes(
        cardImageBytes,
        filename: 'scan-card.jpg',
        contentType: DioMediaType('image', 'jpeg'),
      ),
    });
    final data = await _requestData(
      'POST',
      '/scan/recognize',
      session,
      body,
      idempotencyKey: requestId,
      localPremiumVerified: localPremiumVerified,
    );
    return ScanRecognitionDto.fromJson(data);
  }

  @override
  Future<ScanConfirmationDto> confirmMatch(
    AuthSession session, {
    required String scanId,
    required ScanCollectionItemInput item,
  }) async {
    final data = await _requestData(
      'POST',
      '/scan/${Uri.encodeComponent(scanId)}/confirm',
      session,
      item.toJson(),
    );
    return ScanConfirmationDto.fromJson(data);
  }

  Future<Map<String, Object?>> _requestData(
    String method,
    String path,
    AuthSession session,
    Object? body, {
    String? idempotencyKey,
    bool localPremiumVerified = false,
  }) async {
    final cancelToken = CancelToken();
    late final Response<Object?> response;
    try {
      response = await _dio
          .request<Object?>(
            path,
            data: body,
            cancelToken: cancelToken,
            options: Options(
              method: method,
              headers: {
                'Authorization': 'Bearer ${session.accessToken}',
                if (idempotencyKey != null) 'Idempotency-Key': idempotencyKey,
                if (localPremiumVerified) 'X-Local-Premium-State': 'verified',
              },
              validateStatus: (_) => true,
            ),
          )
          .timeout(
            requestDeadline,
            onTimeout: () {
              cancelToken.cancel(scanRequestTimeoutCode);
              throw const ScanApiException(
                scanRequestTimeoutMessage,
                code: scanRequestTimeoutCode,
              );
            },
          );
    } on DioException {
      if (cancelToken.isCancelled) {
        throw const ScanApiException(
          scanRequestTimeoutMessage,
          code: scanRequestTimeoutCode,
        );
      }
      rethrow;
    }
    final envelope = response.data;
    if (envelope is Map && envelope['success'] == true) {
      final data = envelope['data'];
      if (data is Map) {
        return Map<String, Object?>.from(data);
      }
      return <String, Object?>{};
    }

    throw _apiException(envelope);
  }

  ScanApiException _apiException(Object? envelope) {
    if (envelope is Map) {
      final error = envelope['error'];
      if (error is Map) {
        return ScanApiException(
          _nullableString(error['message']) ??
              'Something went wrong. Please try again.',
          code: _nullableString(error['code']),
          quota: _optionalQuota(envelope['quota']),
        );
      }
    }
    return const ScanApiException('Something went wrong. Please try again.');
  }
}

ScanQuotaDto? _optionalQuota(Object? value) {
  if (value is! Map) return null;
  try {
    return ScanQuotaDto.fromJson(Map<String, Object?>.from(value));
  } on Object {
    return null;
  }
}

List<Map<String, Object?>> _items(Object? value) {
  if (value is! List) {
    throw const ScanApiException('Something went wrong. Please try again.');
  }
  return value.map(_mapItem).toList();
}

Map<String, Object?> _mapItem(Object? item) {
  if (item is! Map) {
    throw const ScanApiException('Something went wrong. Please try again.');
  }
  return Map<String, Object?>.from(item);
}

Map<String, Object?> _requiredMap(Object? value) {
  if (value is! Map) {
    throw const ScanApiException('Something went wrong. Please try again.');
  }
  return Map<String, Object?>.from(value);
}

String _requiredString(Object? value) {
  final normalized = _nullableString(value);
  if (normalized == null) {
    throw const ScanApiException('Something went wrong. Please try again.');
  }
  return normalized;
}

String? _nullableString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _requiredInt(Object? value) {
  if (value is int) return value;
  throw const ScanApiException('Something went wrong. Please try again.');
}

double? _nullableConfidence(Object? value) {
  if (value == null) return null;
  final numeric = value is int
      ? value.toDouble()
      : value is double
      ? value
      : null;
  if (numeric != null && numeric.isFinite && numeric >= 0 && numeric <= 100) {
    return numeric;
  }
  throw const ScanApiException('Something went wrong. Please try again.');
}
