import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/attribution/app_attribution.dart';

void main() {
  test(
    'first install requests ATT only after reading notDetermined and initializes attribution with the final choice',
    () async {
      final events = <String>[];
      final tracking = _TrackingGateway(
        status: AppTrackingStatus.notDetermined,
        requestedStatus: AppTrackingStatus.authorized,
        events: events,
      );
      final attribution = _AttributionGateway(events);
      final coordinator = AppAttributionCoordinator(
        tracking: tracking,
        attribution: attribution,
      );

      await coordinator.prepareForStartup(firstInstall: true);

      expect(events, ['read', 'request', 'attribution:authorized']);
    },
  );

  test(
    'cold start never opens ATT even when status remains notDetermined',
    () async {
      final events = <String>[];
      final coordinator = AppAttributionCoordinator(
        tracking: _TrackingGateway(
          status: AppTrackingStatus.notDetermined,
          requestedStatus: AppTrackingStatus.authorized,
          events: events,
        ),
        attribution: _AttributionGateway(events),
      );

      await coordinator.prepareForStartup(firstInstall: false);

      expect(events, ['read', 'attribution:notDetermined']);
    },
  );

  test('resume refreshes attribution context without requesting ATT', () async {
    final events = <String>[];
    final coordinator = AppAttributionCoordinator(
      tracking: _TrackingGateway(
        status: AppTrackingStatus.denied,
        requestedStatus: AppTrackingStatus.authorized,
        events: events,
      ),
      attribution: _AttributionGateway(events),
    );

    await coordinator.prepareForStartup(firstInstall: false);
    events.clear();
    await coordinator.refreshWithoutPrompt();

    expect(events, ['read', 'attribution:denied']);
  });

  test(
    'resume cannot initialize attribution before startup ATT ordering',
    () async {
      final events = <String>[];
      final coordinator = AppAttributionCoordinator(
        tracking: _TrackingGateway(
          status: AppTrackingStatus.notDetermined,
          requestedStatus: AppTrackingStatus.authorized,
          events: events,
        ),
        attribution: _AttributionGateway(events),
      );

      await coordinator.refreshWithoutPrompt();

      expect(events, isEmpty);
    },
  );

  test('ATT and attribution failures never block the App startup', () async {
    final coordinator = AppAttributionCoordinator(
      tracking: _ThrowingTrackingGateway(),
      attribution: _ThrowingAttributionGateway(),
    );

    await expectLater(
      coordinator.prepareForStartup(firstInstall: true),
      completes,
    );
  });
}

class _TrackingGateway implements AppTrackingGateway {
  _TrackingGateway({
    required this.status,
    required this.requestedStatus,
    required this.events,
  });

  final AppTrackingStatus status;
  final AppTrackingStatus requestedStatus;
  final List<String> events;

  @override
  Future<AppTrackingStatus> readStatus() async {
    events.add('read');
    return status;
  }

  @override
  Future<AppTrackingStatus> requestAuthorization() async {
    events.add('request');
    return requestedStatus;
  }
}

class _AttributionGateway implements AppAttributionGateway {
  _AttributionGateway(this.events);

  final List<String> events;

  @override
  Future<void> updateTrackingStatus(AppTrackingStatus status) async {
    events.add('attribution:${status.name}');
  }
}

class _ThrowingTrackingGateway implements AppTrackingGateway {
  @override
  Future<AppTrackingStatus> readStatus() => Future.error(StateError('read'));

  @override
  Future<AppTrackingStatus> requestAuthorization() =>
      Future.error(StateError('request'));
}

class _ThrowingAttributionGateway implements AppAttributionGateway {
  @override
  Future<void> updateTrackingStatus(AppTrackingStatus status) =>
      Future.error(StateError('attribution'));
}
