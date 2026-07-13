import 'package:flutter_riverpod/flutter_riverpod.dart';

final feedbackRepositoryProvider = Provider<FeedbackRepository>((ref) {
  return LocalFeedbackRepository();
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
  Future<FeedbackReceipt> submit(FeedbackSubmission submission);
}

class LocalFeedbackRepository implements FeedbackRepository {
  @override
  Future<FeedbackReceipt> submit(FeedbackSubmission submission) async {
    final issuedAt = DateTime.now().microsecondsSinceEpoch;
    return FeedbackReceipt(id: 'local-feedback-$issuedAt');
  }
}
