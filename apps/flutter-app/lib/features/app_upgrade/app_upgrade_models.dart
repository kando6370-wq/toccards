class AppUpgradeConfig {
  const AppUpgradeConfig({this.upgradePrompt, this.appStoreUrl});

  final UpgradePrompt? upgradePrompt;
  final String? appStoreUrl;

  factory AppUpgradeConfig.fromJson(Map<String, Object?> json) {
    final promptJson = json['upgrade_prompt'];

    return AppUpgradeConfig(
      upgradePrompt: promptJson is Map<String, Object?>
          ? UpgradePrompt.fromJson(promptJson)
          : null,
      appStoreUrl: _stringOrNull(json['app_store_url']),
    );
  }
}

class UpgradePrompt {
  const UpgradePrompt({
    required this.latestVersion,
    required this.forceUpdate,
    required this.title,
    required this.message,
    required this.storeUrl,
  });

  final String latestVersion;
  final bool forceUpdate;
  final String title;
  final String message;
  final String? storeUrl;

  factory UpgradePrompt.fromJson(Map<String, Object?> json) {
    return UpgradePrompt(
      latestVersion:
          _stringOrNull(json['latest_version']) ??
          _stringOrNull(json['min_version']) ??
          '',
      forceUpdate: json['force_update'] == true,
      title: _stringOrNull(json['title']) ?? 'Update available',
      message:
          _stringOrNull(json['message']) ??
          'Please install the latest Kando version.',
      storeUrl: _stringOrNull(json['store_url']),
    );
  }
}

class AppUpgradeDecision {
  const AppUpgradeDecision._({
    required this.showUpdate,
    required this.forceUpdate,
    required this.title,
    required this.message,
    required this.storeUrl,
    required this.latestVersion,
  });

  const AppUpgradeDecision.none()
    : this._(
        showUpdate: false,
        forceUpdate: false,
        title: '',
        message: '',
        storeUrl: '',
        latestVersion: '',
      );

  const AppUpgradeDecision.update({
    required bool forceUpdate,
    required String title,
    required String message,
    required String storeUrl,
    required String latestVersion,
  }) : this._(
         showUpdate: true,
         forceUpdate: forceUpdate,
         title: title,
         message: message,
         storeUrl: storeUrl,
         latestVersion: latestVersion,
       );

  final bool showUpdate;
  final bool forceUpdate;
  final String title;
  final String message;
  final String storeUrl;
  final String latestVersion;
}

class AppUpgradePolicy {
  const AppUpgradePolicy._();

  static AppUpgradeDecision evaluate({
    required String currentVersion,
    required AppUpgradeConfig config,
  }) {
    final prompt = config.upgradePrompt;
    if (prompt == null) return const AppUpgradeDecision.none();

    final current = _AppVersion.tryParse(currentVersion);
    final latest = _AppVersion.tryParse(prompt.latestVersion);
    final storeUrl = prompt.storeUrl ?? config.appStoreUrl;

    if (current == null || latest == null || storeUrl == null) {
      return const AppUpgradeDecision.none();
    }

    if (current.compareTo(latest) >= 0) {
      return const AppUpgradeDecision.none();
    }

    return AppUpgradeDecision.update(
      forceUpdate: prompt.forceUpdate,
      title: prompt.title,
      message: prompt.message,
      storeUrl: storeUrl,
      latestVersion: prompt.latestVersion,
    );
  }
}

class _AppVersion implements Comparable<_AppVersion> {
  const _AppVersion(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static _AppVersion? tryParse(String value) {
    final core = value.split('+').first.split('-').first.trim();
    final parts = core.split('.');
    if (parts.isEmpty || parts.length > 3) return null;

    final numbers = <int>[];
    for (final part in parts) {
      final number = int.tryParse(part);
      if (number == null || number < 0) return null;
      numbers.add(number);
    }
    while (numbers.length < 3) {
      numbers.add(0);
    }

    return _AppVersion(numbers[0], numbers[1], numbers[2]);
  }

  @override
  int compareTo(_AppVersion other) {
    final majorCompare = major.compareTo(other.major);
    if (majorCompare != 0) return majorCompare;

    final minorCompare = minor.compareTo(other.minor);
    if (minorCompare != 0) return minorCompare;

    return patch.compareTo(other.patch);
  }
}

String? _stringOrNull(Object? value) {
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}
