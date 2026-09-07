import 'subscription_config.dart';

enum SubscriptionPurchaseStatus {
  pending,
  purchased,
  restored,
  canceled,
  failed,
}

enum SubscriptionEntitlementStatus { active, expired, revoked }

class SubscriptionProduct {
  const SubscriptionProduct({
    required this.store,
    required this.storeProductId,
    required this.title,
    required this.description,
    required this.displayPrice,
    required this.rawPrice,
    required this.currencyCode,
    this.storeData,
  });

  final SubscriptionStore store;
  final String storeProductId;
  final String title;
  final String description;
  final String displayPrice;
  final double rawPrice;
  final String currencyCode;
  final Object? storeData;
}

class SubscriptionPurchase {
  const SubscriptionPurchase({
    required this.store,
    required this.storeProductId,
    required this.status,
    required this.verificationData,
    this.transactionId,
    this.transactionDate,
    this.errorCode,
    this.errorMessage,
    this.applicationUserName,
    this.needsCompletion = false,
    this.storeData,
  });

  final SubscriptionStore store;
  final String storeProductId;
  final SubscriptionPurchaseStatus status;
  final String verificationData;
  final String? transactionId;
  final DateTime? transactionDate;
  final String? errorCode;
  final String? errorMessage;
  final String? applicationUserName;
  final bool needsCompletion;
  final Object? storeData;
}

class SubscriptionVerificationRequest {
  const SubscriptionVerificationRequest({
    required this.plan,
    required this.purchase,
  });

  final SubscriptionPlanConfig plan;
  final SubscriptionPurchase purchase;
}

class SubscriptionEntitlement {
  const SubscriptionEntitlement({
    required this.planId,
    required this.entitlementId,
    required this.status,
    this.expiresAt,
  });

  final String planId;
  final String entitlementId;
  final SubscriptionEntitlementStatus status;
  final DateTime? expiresAt;

  bool get isActive => status == SubscriptionEntitlementStatus.active;
}

class SubscriptionFailure {
  const SubscriptionFailure({
    required this.code,
    required this.message,
    this.store,
    this.cause,
  });

  final String code;
  final String message;
  final SubscriptionStore? store;
  final Object? cause;
}

class SubscriptionCatalog {
  const SubscriptionCatalog({required this.products, required this.failures});

  final List<SubscriptionProduct> products;
  final List<SubscriptionFailure> failures;

  bool get hasProducts => products.isNotEmpty;
}

class SubscriptionEvent {
  const SubscriptionEvent({
    this.purchase,
    this.plan,
    this.entitlement,
    this.failure,
  });

  final SubscriptionPurchase? purchase;
  final SubscriptionPlanConfig? plan;
  final SubscriptionEntitlement? entitlement;
  final SubscriptionFailure? failure;
}
