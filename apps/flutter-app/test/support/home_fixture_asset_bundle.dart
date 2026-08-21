import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const homeCardFixtureAsset = 'assets/home/mega_lucario_ex.png';
const homeCardFixturePath = 'test/fixtures/home/mega_lucario_ex.png';

final homeFixtureAssetBundle = _FixtureAssetBundle({
  homeCardFixtureAsset: homeCardFixturePath,
});

class _FixtureAssetBundle extends CachingAssetBundle {
  _FixtureAssetBundle(this._fixturePaths);

  final Map<String, String> _fixturePaths;
  final Map<String, ByteData> _fixtureData = {};

  @override
  Future<ByteData> load(String key) {
    final fixturePath = _fixturePaths[key];
    if (fixturePath == null) return rootBundle.load(key);

    return SynchronousFuture(
      _fixtureData.putIfAbsent(
        key,
        () => ByteData.sublistView(
          Uint8List.fromList(File(fixturePath).readAsBytesSync()),
        ),
      ),
    );
  }
}
