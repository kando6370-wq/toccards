import 'package:flutter_test/flutter_test.dart';
import 'package:kando_app/shared/analytics/analytics_events.dart';
import 'package:kando_app/shared/analytics/app_analytics.dart';

void main() {
  test('analytics event names match the product spreadsheet', () {
    expect(AnalyticsEvent.all, {
      'splash_view',
      'guide1_view',
      'guide2_view',
      'guide3_view',
      'home_view',
      'search_view',
      'portfolio_view',
      'wishlist_view',
      'cardDetails_view',
      'profile_view',
      'support_view',
      'signMethods_view',
      'signin_view',
      'signup_view',
      'setpassword_view',
      'resetpassword_view',
      'scan_view',
      'reviewMatches_view',
      'homePerformance_view',
      'subscribe_view',
      'getCode_click',
      'currency_click',
      'folder_click',
      'mostvaluable_click',
      'trending_click',
      'refresh_click',
      'cancel_click',
      'delete_click',
      'deleteConfirm_click',
      'shareCard_click',
      'camera_click',
      'image_click',
      'collectionItemAdd_click',
      'topMatches_click',
      'signSkip_click',
      'scanClose_click',
      'shareApp_click',
      'sub_click',
      'Google_success',
      'Apple_success',
      'scan_results',
      'sub_success',
      'sub_result',
      'restore_result',
      'api_err',
      'api_timing',
    });
    expect(AnalyticsEvent.all, hasLength(46));
  });

  test('v1.0.1 analytics events match the yellow spreadsheet additions', () {
    expect(
      AnalyticsEvent.all,
      containsAll(const {
        'homePerformance_view',
        'subscribe_view',
        'sub_click',
        'sub_success',
        'sub_result',
        'restore_result',
      }),
    );
  });

  test('analytics property names preserve exact spelling and casing', () {
    expect(AnalyticsProperty.operatingSystem, 'Operating System');
    expect(AnalyticsProperty.appVersion, 'App Version');
    expect(AnalyticsProperty.uid, 'uid');
    expect(AnalyticsProperty.checkDebug, 'check_debug');
    expect(AnalyticsProperty.subPlan, 'sub_plan');
    expect(AnalyticsProperty.scene, 'Scene');
    expect(AnalyticsProperty.plan, 'plan');
    expect(AnalyticsProperty.currency, 'currency');
    expect(AnalyticsProperty.price, 'price');
    expect(AnalyticsProperty.originalId, 'original_id');
    expect(AnalyticsProperty.results, 'Results');
    expect(AnalyticsProperty.ipType, 'IP type');
    expect(AnalyticsProperty.tabType, 'tab type');
    expect(AnalyticsProperty.collectionType, 'collection type');
    expect(AnalyticsProperty.gradeType, 'grade type');
    expect(AnalyticsProperty.entrySource, 'entry source');
    expect(AnalyticsProperty.scanResults, 'scan results');
    expect(AnalyticsProperty.apiName, 'api_name');
    expect(AnalyticsProperty.apiMessage, 'api_messsage');
    expect(AnalyticsProperty.apiParams, 'api_params');
  });

  test('subscription values preserve spreadsheet spelling and casing', () {
    expect(AnalyticsValue.sceneGuide, 'guide');
    expect(AnalyticsValue.sceneUsual, 'Usual');
    expect(AnalyticsValue.sceneIcon, 'icon');
    expect(AnalyticsValue.sceneBanner, 'banner');
    expect(AnalyticsValue.sceneTimeRange, 'timeRange');
    expect(AnalyticsValue.sceneHomePerformance, 'homePerformance');
    expect(AnalyticsValue.sceneCardDetailPerformance, 'cardDetailPerformance');
    expect(AnalyticsValue.sceneScanTip, 'scanTip');
    expect(AnalyticsValue.sceneScanTimes, 'scanTimes');
    expect(AnalyticsValue.sceneScanWaiting, 'scanWating');
    expect(AnalyticsValue.resultSuccess, 'success');
    expect(AnalyticsValue.resultCancel, 'cancel');
    expect(AnalyticsValue.resultFailed, 'failed');
    expect(AnalyticsValue.resultNotFound, 'notFound');
  });

  test('IP values normalize to the spreadsheet enums', () {
    expect(analyticsIpType('pokemon'), 'Pokémon');
    expect(analyticsIpType('mtg'), 'Magic');
    expect(analyticsIpType('one-piece'), 'OnePiece');
    expect(analyticsIpType('star_wars'), 'StarWarsFleshandBlood');
    expect(analyticsIpType('flesh-and-blood'), 'StarWarsFleshandBlood');
    expect(analyticsIpType('Basketball'), 'basketball');
  });

  test('scan item debounce keys keep batch add events distinct', () {
    final events = <String>[];
    final analytics = AppAnalytics.recording((event, _) => events.add(event));
    const properties = {
      AnalyticsProperty.ipType: 'Pokémon',
      AnalyticsProperty.gradeType: AnalyticsValue.gradeNormal,
      AnalyticsProperty.entrySource: AnalyticsValue.sourceScan,
    };

    analytics.track(
      AnalyticsEvent.collectionItemAddClick,
      properties: properties,
      debounceKey: 'scan-1',
    );
    analytics.track(
      AnalyticsEvent.collectionItemAddClick,
      properties: properties,
      debounceKey: 'scan-2',
    );
    analytics.track(
      AnalyticsEvent.collectionItemAddClick,
      properties: properties,
      debounceKey: 'scan-2',
    );

    expect(events, [
      AnalyticsEvent.collectionItemAddClick,
      AnalyticsEvent.collectionItemAddClick,
    ]);
  });
}
