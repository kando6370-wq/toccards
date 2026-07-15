import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_models.dart';
import 'package:kando_app/features/app_upgrade/app_upgrade_repository.dart';
import 'package:kando_app/features/profile/profile_actions.dart';

void main() {
  test(
    'legal action fails when operations has not configured a URL because the UI must not report a fake success',
    () async {
      final actions = PluginProfileActions(
        _FakeAppUpgradeRepository(const AppUpgradeConfig()),
      );

      await expectLater(actions.openTerms(), throwsStateError);
    },
  );

  test(
    'legal action rejects non-web URLs because runtime config is an external web link',
    () async {
      final actions = PluginProfileActions(
        _FakeAppUpgradeRepository(
          const AppUpgradeConfig(termsUrl: 'ftp://example.com/terms'),
        ),
      );

      await expectLater(actions.openTerms(), throwsStateError);
    },
  );
}

class _FakeAppUpgradeRepository implements AppUpgradeRepository {
  const _FakeAppUpgradeRepository(this.config);

  final AppUpgradeConfig config;

  @override
  Future<AppUpgradeConfig> loadConfig() async => config;
}
