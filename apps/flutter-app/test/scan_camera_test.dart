// Uses the platform interface from the pinned camera plugin for test injection.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/features/scan/scan_camera.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final originalPlatform = CameraPlatform.instance;
  late _TestCamera camera;
  const deviceInfo = MethodChannel('dev.fluttercommunity.plus/device_info');
  const cropChannel = MethodChannel('com.cardai.tcg/scan-image-processor');
  const rotationChannel = MethodChannel('com.cardai.tcg/duo-scan-rotation');
  const rotationEvents = 'com.cardai.tcg/duo-scan-rotation/1';
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void mockIosDevice(String machine, {required bool isPhysicalDevice}) {
    messenger.setMockMethodCallHandler(deviceInfo, (call) async {
      expect(call.method, 'getDeviceInfo');
      return {
        'name': 'iPhone',
        'systemName': 'iOS',
        'systemVersion': '27.1',
        'model': 'iPhone',
        'modelName': 'iPhone',
        'localizedModel': 'iPhone',
        'freeDiskSize': 1,
        'totalDiskSize': 2,
        'physicalRamSize': 2,
        'availableRamSize': 1,
        'isiOSAppOnMac': false,
        'isPhysicalDevice': isPhysicalDevice,
        'utsname': {
          'sysname': 'Darwin',
          'nodename': 'iPhone',
          'release': '',
          'version': '',
          'machine': machine,
        },
      };
    });
  }

  setUp(() {
    camera = _TestCamera();
    CameraPlatform.instance = camera;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(deviceInfo, null);
    messenger.setMockMethodCallHandler(cropChannel, null);
    messenger.setMockMethodCallHandler(rotationChannel, null);
    CameraPlatform.instance = originalPlatform;
    debugDefaultTargetPlatformOverride = null;
  });

  test('iOS camera without flash stays open for scanning', () async {
    camera.flashError = 'Device does not have flash capabilities';

    final session = await const PluginScanCameraFactory().open();

    expect(session, isNotNull);
    expect(session!.flashEnabled, isFalse);
    expect(camera.orientation, DeviceOrientation.portraitUp);
    expect(camera.disposed, isFalse);
    await session.dispose();
    expect(camera.disposed, isTrue);
  });

  test(
    'other flash initialization failures still release the camera',
    () async {
      camera.flashError = 'Device does not support this specific flash mode';

      expect(await const PluginScanCameraFactory().open(), isNull);
      expect(camera.disposed, isTrue);
    },
  );

  testWidgets('Duo simulator uses native zero turns for preview and capture', (
    tester,
  ) async {
    try {
      mockIosDevice('iPhone19,4', isPhysicalDevice: false);
      final directory = Directory.systemTemp.createTempSync('duo-scan-test-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final photo = File('${directory.path}/scan.jpg')..writeAsBytesSync([3]);
      var nativeCaptures = 0;
      messenger.setMockMethodCallHandler(rotationChannel, (call) async {
        switch (call.method) {
          case 'enable':
            expect(call.arguments, {'cameraId': 1});
            return 0;
          case 'takePicture':
            nativeCaptures++;
            expect(call.arguments, {'cameraId': 1, 'previewTurns': 0});
            return {'path': photo.path, 'cropTurns': 0};
          default:
            fail('Unexpected camera method: ${call.method}');
        }
      });
      final session = (await tester.runAsync(
        const PluginScanCameraFactory().open,
      ))!;
      addTearDown(session.dispose);
      expect(camera.orientation, DeviceOrientation.portraitUp);
      await tester.pumpWidget(MaterialApp(home: session.buildPreview()));
      final preview = tester.widget<SizedBox>(
        find.descendant(
          of: find.byType(FittedBox),
          matching: find.byType(SizedBox),
        ),
      );
      expect(preview.width, 1920);
      expect(preview.height, 1080);
      messenger.setMockMethodCallHandler(cropChannel, (call) async {
        expect(call.method, 'cropViewfinder');
        expect(call.arguments['image'], [3]);
        expect(call.arguments['preview_width'], preview.width);
        expect(call.arguments['preview_height'], preview.height);
        final frame = (call.arguments['frame'] as List).cast<double>();
        expect(frame[0], closeTo(.4296875, 1e-9));
        expect(frame[1], closeTo(.25, 1e-9));
        expect(frame[2], closeTo(.5703125, 1e-9));
        expect(frame[3], closeTo(.75, 1e-9));
        return Uint8List.fromList([2]);
      });
      final cropped = await tester.runAsync(
        () => session.takePhoto(
          viewport: const Size(400, 800),
          viewfinder: const Rect.fromLTWH(100, 200, 200, 400),
        ),
      );
      expect(nativeCaptures, 1);
      expect(cropped?.viewfinderCropped, isTrue);
      expect(cropped?.bytes, [2]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final (machine, isPhysicalDevice) in [
    ('iPhone19,4', true),
    ('iPhone19,4', false),
    ('iPhone18,1', false),
    ('iPhone19,2', true),
  ]) {
    test(
      '$machine with isPhysicalDevice=$isPhysicalDevice locks portrait',
      () async {
        mockIosDevice(machine, isPhysicalDevice: isPhysicalDevice);
        final expectRotationRequest = machine == 'iPhone19,4';
        var rotationRequests = 0;
        messenger.setMockMethodCallHandler(rotationChannel, (call) async {
          rotationRequests++;
          expect(call.method, 'enable');
          return null; // 原生 iOS 16 分支回退到标准取景和拍照。
        });
        final session = (await const PluginScanCameraFactory().open())!;
        expect(rotationRequests, expectRotationRequest ? 1 : 0);
        addTearDown(session.dispose);
        expect(camera.orientation, DeviceOrientation.portraitUp);
      },
    );
  }

  testWidgets('Duo real-device rotation updates preview size and crop', (
    tester,
  ) async {
    try {
      mockIosDevice('iPhone19,4', isPhysicalDevice: true);
      final directory = Directory.systemTemp.createTempSync('duo-scan-test-');
      addTearDown(() => directory.deleteSync(recursive: true));
      final photo = File('${directory.path}/scan.jpg')..writeAsBytesSync([3]);
      var nativeCaptures = 0;
      messenger.setMockMethodCallHandler(rotationChannel, (call) async {
        switch (call.method) {
          case 'enable':
            expect(call.arguments, {'cameraId': 1});
            return 1;
          case 'takePicture':
            nativeCaptures++;
            expect(call.arguments, {'cameraId': 1, 'previewTurns': 0});
            return {'path': photo.path, 'cropTurns': 3};
          default:
            fail('Unexpected camera method: ${call.method}');
        }
      });
      final session = (await tester.runAsync(
        const PluginScanCameraFactory().open,
      ))!;
      addTearDown(session.dispose);
      expect(camera.orientation, DeviceOrientation.portraitUp);
      await tester.pumpWidget(MaterialApp(home: session.buildPreview()));
      Size previewSize() {
        final preview = tester.widget<SizedBox>(
          find.descendant(
            of: find.byType(FittedBox),
            matching: find.byType(SizedBox),
          ),
        );
        return Size(preview.width!, preview.height!);
      }

      expect(previewSize(), const Size(1080, 1920));
      await messenger.handlePlatformMessage(
        rotationEvents,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('previewTurns', 0),
        ),
        (_) {},
      );
      const viewport = Size(480, 540);
      const viewfinder = Rect.fromLTWH(90, 60, 300, 420);
      await tester.runAsync(() async {
        await expectLater(
          session.takePhoto(viewport: viewport, viewfinder: viewfinder),
          throwsStateError,
        );
      });
      expect(nativeCaptures, 0);
      await tester.pump();
      expect(previewSize(), const Size(1920, 1080));
      messenger.setMockMethodCallHandler(cropChannel, (call) async {
        expect(call.method, 'cropViewfinder');
        expect(call.arguments['image'], [3]);
        expect(call.arguments['preview_width'], previewSize().width);
        expect(call.arguments['preview_height'], previewSize().height);
        expect(call.arguments['clockwise_quarter_turns'], 3);
        return Uint8List.fromList([4]);
      });
      final cropped = await tester.runAsync(
        () => session.takePhoto(viewport: viewport, viewfinder: viewfinder),
      );
      expect(nativeCaptures, 1);
      expect(cropped?.bytes, [4]);
      expect(cropped?.viewfinderCropped, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test(
    'Android initialization still turns flash off and locks portrait',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;

      final session = await const PluginScanCameraFactory().open();

      expect(session, isNotNull);
      expect(camera.flashMode, FlashMode.off);
      expect(camera.orientation, DeviceOrientation.portraitUp);
      expect(camera.imageFormat, ImageFormatGroup.yuv420);
      await session!.dispose();
    },
  );
}

class _TestCamera extends CameraPlatform {
  String? flashError;
  FlashMode? flashMode;
  DeviceOrientation? orientation;
  ImageFormatGroup? imageFormat;
  bool disposed = false;

  @override
  Future<List<CameraDescription>> availableCameras() async => const [
    CameraDescription(
      name: 'back',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    ),
  ];

  @override
  Future<int> createCameraWithSettings(
    CameraDescription description,
    MediaSettings? mediaSettings,
  ) async => 1;

  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();

  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int cameraId) =>
      Stream.value(
        CameraInitializedEvent(
          cameraId,
          1920,
          1080,
          ExposureMode.auto,
          false,
          FocusMode.auto,
          false,
        ),
      );

  @override
  Stream<CameraErrorEvent> onCameraError(int cameraId) => Stream.multi((_) {});

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {
    imageFormat = imageFormatGroup;
  }

  @override
  Future<void> lockCaptureOrientation(
    int cameraId,
    DeviceOrientation requestedOrientation,
  ) async {
    orientation = requestedOrientation;
  }

  @override
  Future<void> setFlashMode(int cameraId, FlashMode mode) async {
    flashMode = mode;
    if (flashError != null) {
      throw PlatformException(code: 'setFlashModeFailed', message: flashError);
    }
  }

  @override
  Widget buildPreview(int cameraId) => const ColoredBox(color: Colors.black);

  @override
  Future<XFile> takePicture(int cameraId) async =>
      XFile.fromData(Uint8List.fromList([1]), name: 'scan.jpg');

  @override
  Future<void> dispose(int cameraId) async {
    disposed = true;
  }
}
