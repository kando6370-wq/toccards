import '../analytics/analytics_events.dart';

const _firebaseStringLimit = 100;

const _firebaseParameterNames = <String, String>{
  AnalyticsProperty.operatingSystem: 'operating_system',
  AnalyticsProperty.appVersion: 'app_version',
  AnalyticsProperty.uid: 'uid',
  AnalyticsProperty.checkDebug: 'check_debug',
  AnalyticsProperty.subPlan: 'sub_plan',
  AnalyticsProperty.scene: 'scene',
  AnalyticsProperty.plan: 'plan',
  AnalyticsProperty.currency: 'currency',
  AnalyticsProperty.price: 'price',
  AnalyticsProperty.originalId: 'original_id',
  AnalyticsProperty.results: 'results',
  AnalyticsProperty.ipType: 'ip_type',
  AnalyticsProperty.tabType: 'tab_type',
  AnalyticsProperty.collectionType: 'collection_type',
  AnalyticsProperty.gradeType: 'grade_type',
  AnalyticsProperty.entrySource: 'entry_source',
  AnalyticsProperty.timing: 'timing',
  AnalyticsProperty.scanResults: 'scan_results',
  AnalyticsProperty.apiName: 'api_name',
  AnalyticsProperty.apiMessage: 'api_messsage',
  AnalyticsProperty.apiParams: 'api_params',
};

Map<String, Object> firebaseAnalyticsParameters(
  Map<String, Object?> properties,
) {
  final parameters = <String, Object>{};
  for (final entry in properties.entries) {
    final value = _firebaseValue(entry.value);
    if (value == null) continue;
    parameters[_firebaseParameterName(entry.key)] = value;
  }
  return parameters;
}

String _firebaseParameterName(String source) {
  var name =
      _firebaseParameterNames[source] ??
      source.replaceAll(RegExp('[^a-zA-Z0-9_]'), '_');
  if (name.isEmpty || !RegExp('^[a-zA-Z]').hasMatch(name)) {
    name = 'param_$name';
  }
  if (name.startsWith('firebase_') ||
      name.startsWith('google_') ||
      name.startsWith('ga_')) {
    name = 'custom_$name';
  }
  return name.length <= 40 ? name : name.substring(0, 40);
}

Object? _firebaseValue(Object? value) {
  return switch (value) {
    null => null,
    bool flag => flag ? 1 : 0,
    num number => number,
    String text =>
      text.length <= _firebaseStringLimit
          ? text
          : text.substring(0, _firebaseStringLimit),
    _ => _truncate(value.toString()),
  };
}

String _truncate(String value) {
  return value.length <= _firebaseStringLimit
      ? value
      : value.substring(0, _firebaseStringLimit);
}
