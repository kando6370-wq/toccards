abstract final class AnalyticsEvent {
  static const splashView = 'splash_view';
  static const guide1View = 'guide1_view';
  static const guide2View = 'guide2_view';
  static const guide3View = 'guide3_view';
  static const homeView = 'home_view';
  static const searchView = 'search_view';
  static const portfolioView = 'portfolio_view';
  static const wishlistView = 'wishlist_view';
  static const cardDetailsView = 'cardDetails_view';
  static const profileView = 'profile_view';
  static const supportView = 'support_view';
  static const signMethodsView = 'signMethods_view';
  static const signinView = 'signin_view';
  static const signupView = 'signup_view';
  static const setpasswordView = 'setpassword_view';
  static const resetpasswordView = 'resetpassword_view';
  static const scanView = 'scan_view';
  static const reviewMatchesView = 'reviewMatches_view';

  static const getCodeClick = 'getCode_click';
  static const currencyClick = 'currency_click';
  static const folderClick = 'folder_click';
  static const mostvaluableClick = 'mostvaluable_click';
  static const trendingClick = 'trending_click';
  static const refreshClick = 'refresh_click';
  static const cancelClick = 'cancel_click';
  static const deleteClick = 'delete_click';
  static const deleteConfirmClick = 'deleteConfirm_click';
  static const shareCardClick = 'shareCard_click';
  static const cameraClick = 'camera_click';
  static const imageClick = 'image_click';
  static const collectionItemAddClick = 'collectionItemAdd_click';
  static const topMatchesClick = 'topMatches_click';
  static const signSkipClick = 'signSkip_click';
  static const scanCloseClick = 'scanClose_click';
  static const shareAppClick = 'shareApp_click';

  static const googleSuccess = 'Google_success';
  static const appleSuccess = 'Apple_success';
  static const scanResults = 'scan_results';

  static const apiError = 'api_err';
  static const apiTiming = 'api_timing';

  static const all = <String>{
    splashView,
    guide1View,
    guide2View,
    guide3View,
    homeView,
    searchView,
    portfolioView,
    wishlistView,
    cardDetailsView,
    profileView,
    supportView,
    signMethodsView,
    signinView,
    signupView,
    setpasswordView,
    resetpasswordView,
    scanView,
    reviewMatchesView,
    getCodeClick,
    currencyClick,
    folderClick,
    mostvaluableClick,
    trendingClick,
    refreshClick,
    cancelClick,
    deleteClick,
    deleteConfirmClick,
    shareCardClick,
    cameraClick,
    imageClick,
    collectionItemAddClick,
    topMatchesClick,
    signSkipClick,
    scanCloseClick,
    shareAppClick,
    googleSuccess,
    appleSuccess,
    scanResults,
    apiError,
    apiTiming,
  };
}

abstract final class AnalyticsProperty {
  static const operatingSystem = 'Operating System';
  static const appVersion = 'App Version';
  static const uid = 'uid';
  static const checkDebug = 'check_debug';
  static const subPlan = 'sub_plan';

  static const ipType = 'IP type';
  static const tabType = 'tab type';
  static const collectionType = 'collection type';
  static const gradeType = 'grade type';
  static const entrySource = 'entry source';
  static const timing = 'timing';
  static const scanResults = 'scan results';
  static const apiName = 'api_name';
  static const apiMessage = 'api_messsage';
  static const apiParams = 'api_params';
}

abstract final class AnalyticsValue {
  static const collectionPortfolio = 'portfolio';
  static const collectionWishlist = 'wishlist';
  static const collectionNormal = 'normal';

  static const tabCard = 'card';
  static const tabSet = 'set';
  static const tabSetCard = 'set card';

  static const gradeNormal = 'normal';
  static const gradeGraded = 'graded';

  static const sourceScan = 'scan';
  static const sourceSearch = 'search';
  static const sourceTrendingToday = 'trending today';
  static const sourceEdit = 'edit';

  static const scanFailed = 'failed';
  static const scanSuccess = 'success';
  static const scanNotFound = 'notfound';
}

String analyticsIpType(String? value) {
  final normalized = (value ?? '').toLowerCase().replaceAll(
    RegExp('[^a-z0-9]'),
    '',
  );
  if (normalized.contains('pokemon')) return 'Pokémon';
  if (normalized.contains('magic') || normalized == 'mtg') return 'Magic';
  if (normalized.contains('onepiece')) return 'OnePiece';
  if (normalized.contains('disney')) return 'Disney';
  if (normalized.contains('digimon')) return 'Digimon';
  if (normalized.contains('starwars') || normalized.contains('fleshandblood')) {
    return 'StarWarsFleshandBlood';
  }
  if (normalized.contains('basketball')) return 'basketball';
  if (normalized.contains('football')) return 'football';
  if (normalized.contains('soccer')) return 'soccer';
  return value?.trim() ?? '';
}
