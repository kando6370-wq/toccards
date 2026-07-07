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
}

class CollectionItem {
  const CollectionItem({
    required this.id,
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
    required this.change30dPercent,
    required this.createdAtSort,
  });

  final String id;
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
  final double? change30dPercent;
  final int createdAtSort;

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
  });

  final List<CollectionFolder> folders;
  final List<CollectionItem> portfolioItems;
  final List<CollectionItem> wishlistItems;

  CollectionFolder get defaultFolder {
    return folders.firstWhere((folder) => folder.isDefault);
  }
}
