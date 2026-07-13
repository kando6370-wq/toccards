const emailEmptyMessage = 'Please enter your email.';
const emailInvalidMessage = 'Please enter a valid email address.';

String normalizedEmail(String value) {
  return value.trim().toLowerCase();
}

String? emailValidationMessage(String email) {
  if (email.isEmpty) {
    return emailEmptyMessage;
  }

  if (email.length > 254 || RegExp(r'\s').hasMatch(email)) {
    return emailInvalidMessage;
  }

  final parts = email.split('@');
  if (parts.length != 2) {
    return emailInvalidMessage;
  }

  final localPart = parts[0];
  final domain = parts[1];
  if (localPart.isEmpty || domain.isEmpty || !domain.contains('.')) {
    return emailInvalidMessage;
  }

  final labels = domain.split('.');
  if (labels.any((label) => label.isEmpty)) {
    return emailInvalidMessage;
  }

  return null;
}
