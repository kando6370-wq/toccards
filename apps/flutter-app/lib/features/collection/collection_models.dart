enum CollectionTab { portfolio, wishlist }

enum CollectionSort {
  newest,
  valueDesc,
  valueAsc,
  changeDesc,
  nameAsc,
  performanceDesc,
}

enum CreateFolderStatus {
  success,
  premiumRequired,
  entitlementSyncRequired,
  failed,
}

class CreateFolderResult {
  const CreateFolderResult(this.status, {this.folder});

  final CreateFolderStatus status;
  final CollectionFolder? folder;
}

class CollectionFolder {
  const CollectionFolder({
    required this.id,
    required this.name,
    required this.isDefault,
  });

  final String id;
  final String name;
  final bool isDefault;

  CollectionFolder copyWith({String? name, bool? isDefault}) {
    return CollectionFolder(
      id: id,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
    );
  }
}

class CollectionItem {
  const CollectionItem({
    required this.id,
    required this.cardRef,
    required this.folderId,
    required this.name,
    required this.setName,
    required this.number,
    required this.rarity,
    required this.game,
    required this.language,
    required this.finish,
    required this.grader,
    required this.condition,
    required this.grade,
    required this.quantity,
    required this.marketValueUsd,
    required this.previous30dPriceUsd,
    this.increasePercent,
    required this.addedAtSort,
    this.imageUrl,
  });

  final String id;
  final String cardRef;
  final String? folderId;
  final String name;
  final String setName;
  final String number;
  final String rarity;
  final String game;
  final String language;
  final String finish;
  final String grader;
  final String? condition;
  final double? grade;
  final int quantity;
  final double? marketValueUsd;
  final double? previous30dPriceUsd;
  final double? increasePercent;
  final int addedAtSort;
  final String? imageUrl;

  bool get isGraded => grader != 'Raw';

  String get statusText {
    if (isGraded) {
      final value = grade;
      final gradeText = value == null
          ? '-'
          : value == value.truncateToDouble()
          ? value.toStringAsFixed(0)
          : value.toStringAsFixed(1);
      return '$grader $gradeText';
    }

    return 'Raw · ${condition ?? '-'}';
  }

  String get searchableText {
    return '$name $setName $number $game'.toLowerCase();
  }
}

class CollectionDashboard {
  const CollectionDashboard({
    required this.folders,
    required this.portfolioItems,
    required this.wishlistItems,
    this.currencyCode = 'USD',
    this.amountHidden = false,
  });

  final List<CollectionFolder> folders;
  final List<CollectionItem> portfolioItems;
  final List<CollectionItem> wishlistItems;
  final String currencyCode;
  final bool amountHidden;

  CollectionFolder get defaultFolder {
    return folders.firstWhere((folder) => folder.isDefault);
  }

  CollectionDashboard copyWith({
    List<CollectionFolder>? folders,
    List<CollectionItem>? portfolioItems,
    List<CollectionItem>? wishlistItems,
    String? currencyCode,
    bool? amountHidden,
  }) {
    return CollectionDashboard(
      folders: folders ?? this.folders,
      portfolioItems: portfolioItems ?? this.portfolioItems,
      wishlistItems: wishlistItems ?? this.wishlistItems,
      currencyCode: currencyCode ?? this.currencyCode,
      amountHidden: amountHidden ?? this.amountHidden,
    );
  }
}

class CollectionPageResult {
  const CollectionPageResult({
    required this.dashboard,
    required this.folderId,
    required this.total,
    this.baseCount,
    required this.page,
    required this.pageSize,
  });

  final CollectionDashboard dashboard;
  final String? folderId;
  final int total;
  final int? baseCount;
  final int page;
  final int pageSize;
}

class CollectionFolderTotals {
  const CollectionFolderTotals({
    required this.folderId,
    required this.itemCount,
    required this.cardCount,
    required this.gradedCount,
    required this.totalValueUsd,
    required this.languages,
  });

  final String folderId;
  final int itemCount;
  final int cardCount;
  final int gradedCount;
  final double? totalValueUsd;
  final List<String> languages;
}

class CollectionSummaryResult {
  const CollectionSummaryResult({
    required this.folders,
    required this.wishlistCount,
    required this.wishlistLanguages,
    this.games = const [],
  });

  final Map<String, CollectionFolderTotals> folders;
  final int wishlistCount;
  final List<String> wishlistLanguages;
  final List<String> games;
}
