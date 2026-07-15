import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:kando_app/features/auth/auth_models.dart';
import 'package:kando_app/features/auth/auth_repository.dart';

const scanApiBaseUrl = authApiBaseUrl;

Dio createScanDio({String baseUrl = scanApiBaseUrl}) {
  return Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 120),
    ),
  );
}

class ScanApiException implements Exception {
  const ScanApiException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class ScanRecognitionDto {
  const ScanRecognitionDto({
    required this.scanId,
    required this.recognitionStatus,
    required this.results,
  });

  final String scanId;
  final String recognitionStatus;
  final List<ScanResultDto> results;

  factory ScanRecognitionDto.fromJson(Map<String, Object?> json) {
    return ScanRecognitionDto(
      scanId: _requiredString(json['scan_id']),
      recognitionStatus: _requiredString(json['recognition_status']),
      results: _items(json['results']).map(ScanResultDto.fromJson).toList(),
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
      confidence: _nullableDouble(json['confidence']),
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

abstract interface class ScanApi {
  Future<ScanRecognitionDto> recognizeImage(
    AuthSession session, {
    required Uint8List imageBytes,
    required String fileName,
    required String platform,
    required String appVersion,
    String? deviceModel,
    String? osVersion,
  });
  Future<ScanConfirmationDto> confirmMatch(
    AuthSession session, {
    required String scanId,
    required String folderId,
    required String cardRef,
  });
}

class ScanApiClient implements ScanApi {
  const ScanApiClient(this._dio);

  final Dio _dio;

  @override
  Future<ScanRecognitionDto> recognizeImage(
    AuthSession session, {
    required Uint8List imageBytes,
    required String fileName,
    required String platform,
    required String appVersion,
    String? deviceModel,
    String? osVersion,
  }) async {
    final form = FormData.fromMap({
      'image': MultipartFile.fromBytes(imageBytes, filename: fileName),
      'platform': platform,
      'app_version': appVersion,
      if (deviceModel != null) 'device_model': deviceModel,
      if (osVersion != null) 'os_version': osVersion,
    });
    final data = await _requestData('POST', '/scan/recognize', session, form);
    return ScanRecognitionDto.fromJson(data);
  }

  @override
  Future<ScanConfirmationDto> confirmMatch(
    AuthSession session, {
    required String scanId,
    required String folderId,
    required String cardRef,
  }) async {
    final data = await _requestData(
      'POST',
      '/scan/${Uri.encodeComponent(scanId)}/confirm',
      session,
      {'folder_id': folderId, 'card_ref': cardRef},
    );
    return ScanConfirmationDto.fromJson(data);
  }

  Future<Map<String, Object?>> _requestData(
    String method,
    String path,
    AuthSession session,
    Object body,
  ) async {
    final response = await _dio.request<Object?>(
      path,
      data: body,
      options: Options(
        method: method,
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
        validateStatus: (_) => true,
      ),
    );
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
        );
      }
    }
    return const ScanApiException('Something went wrong. Please try again.');
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

double? _nullableDouble(Object? value) {
  if (value == null) return null;
  if (value is int) return value.toDouble();
  if (value is double) return value;
  throw const ScanApiException('Something went wrong. Please try again.');
}
