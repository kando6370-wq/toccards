import 'dart:convert';
import 'dart:io';

const requiredSubscriptionKeys = <String>[
  'SUBSCRIPTION_APP_STORE_WEEKLY_ID',
  'SUBSCRIPTION_APP_STORE_YEARLY_ID',
  'SUBSCRIPTION_APP_STORE_LIFETIME_ID',
];

const requiredProductionAttributionKeys = <String>[
  'SINGULAR_API_KEY',
  'SINGULAR_SECRET_KEY',
];

List<String> validateReleaseConfig(
  Map<String, Object?> config,
  String environment,
) {
  final errors = <String>[];
  if (config['APP_ENV'] != environment) {
    errors.add('APP_ENV must equal $environment.');
  }
  final requiredKeys = <String>[
    ...requiredSubscriptionKeys,
    if (environment == 'production') ...requiredProductionAttributionKeys,
  ];
  for (final key in requiredKeys) {
    final value = config[key];
    if (value is! String || value.trim().isEmpty) {
      errors.add('$key must be a non-empty string.');
    }
  }
  final productIds = requiredSubscriptionKeys
      .map((key) => config[key])
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toList();
  if (productIds.toSet().length != productIds.length) {
    errors.add('Subscription Product IDs must be unique.');
  }
  return errors;
}

void main(List<String> arguments) {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart tool/validate_release_config.dart <config.json> '
      '<test|production>',
    );
    exitCode = 64;
    return;
  }

  try {
    final decoded = jsonDecode(File(arguments[0]).readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Root JSON value must be an object.');
    }
    final errors = validateReleaseConfig(decoded, arguments[1]);
    if (errors.isNotEmpty) {
      for (final error in errors) {
        stderr.writeln(error);
      }
      exitCode = 1;
    }
  } on Object catch (error) {
    stderr.writeln('Invalid release configuration: $error');
    exitCode = 1;
  }
}
