import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

final feedbackRepositoryProvider = Provider<FeedbackRepository>((ref) {
  return HttpFeedbackRepository(ref.watch(authDioProvider));
});

class FeedbackSubmission {
  const FeedbackSubmission({
    required this.email,
    required this.types,
    required this.functions,
    required this.message,
  });

  final String email;
  final List<String> types;
  final List<String> functions;
  final String message;
}

class FeedbackReceipt {
  const FeedbackReceipt({required this.id});

  final String id;
}

abstract class FeedbackRepository {
  Future<FeedbackReceipt> submit(
    AuthSession session,
    FeedbackSubmission submission,
  );
}

class FeedbackApiException implements Exception {
  const FeedbackApiException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

class HttpFeedbackRepository implements FeedbackRepository {
  const HttpFeedbackRepository(this._dio);

  final Dio _dio;

  @override
  Future<FeedbackReceipt> submit(
    AuthSession session,
    FeedbackSubmission submission,
  ) async {
    final response = await _dio.post<Object?>(
      '/feedback',
      data: {
        'email': submission.email,
        'types': submission.types,
        'functions': submission.functions,
        'message': submission.message,
      },
      options: Options(
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
        validateStatus: (_) => true,
      ),
    );
    final envelope = response.data;
    if (envelope is Map && envelope['success'] == true) {
      final data = envelope['data'];
      if (data is Map && data['id'] is String) {
        return FeedbackReceipt(id: data['id'] as String);
      }
    }

    throw _apiException(envelope);
  }

  FeedbackApiException _apiException(Object? envelope) {
    if (envelope is Map) {
      final error = envelope['error'];
      if (error is Map) {
        return FeedbackApiException(
          _nullableString(error['message']) ??
              'Unable to submit feedback. Please try again later.',
          code: _nullableString(error['code']),
        );
      }
    }
    return const FeedbackApiException(
      'Unable to submit feedback. Please try again later.',
    );
  }
}

String? _nullableString(Object? value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
