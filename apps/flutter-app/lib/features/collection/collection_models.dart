enum CollectionTab { portfolio, wishlist }

enum CollectionSort { newest, valueDesc, changeDesc, nameAsc }

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
    required this.game,
    required this.language,
    required this.finish,
    required this.grader,
    required this.condition,
    required this.grade,
    required this.quantity,
    required this.marketValueUsd,
    required this.previous30dPriceUsd,
    required this.addedAtSort,
    this.imageUrl,
  });

  final String id;
  final String cardRef;
  final String? folderId;
  final String name;
  final String setName;
  final String number;
  final String game;
  final String language;
  final String finish;
  final String grader;
  final String? condition;
  final double? grade;
  final int quantity;
  final double? marketValueUsd;
  final double? previous30dPriceUsd;
  final int addedAtSort;
  final String? imageUrl;

  bool get isGraded => grader != 'Raw';

  String get statusText {
    if (isGraded) {
      return '$grader ${grade?.toStringAsFixed(0) ?? '-'}';
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
