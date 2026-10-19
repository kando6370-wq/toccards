enum SubscriptionPageType { page, modal }

enum DisplayProductType { subscription, nonConsumable }

class SubscriptionCopy {
  const SubscriptionCopy({
    required this.name,
    this.subtitle = '',
    this.badge = '',
    this.priceNote = '',
    this.cta = '',
    this.billingNote = '',
    this.autoBillingNote = true,
  });
  final String name, subtitle, badge, priceNote, cta, billingNote;
  final bool autoBillingNote;

  factory SubscriptionCopy.fromJson(Map<String, Object?> json) {
    final mode = json['billing_note_mode'];
    if (mode != 'auto' && mode != 'custom') {
      throw const FormatException('Invalid billing mode');
    }
    return SubscriptionCopy(
      name: _text(json, 'name', 100, required: true),
      subtitle: _description(json, 'subtitle', 300),
      badge: _description(json, 'badge', 100),
      priceNote: _description(json, 'price_note', 200),
      cta: _cta(json),
      autoBillingNote: mode == 'auto',
      billingNote: mode == 'custom'
          ? _description(json, 'billing_note', 500)
          : '',
    );
  }
}

class SubscriptionTrial {
  const SubscriptionTrial({required this.productId, required this.copy});
  final String productId;
  final SubscriptionCopy copy;
}

class SubscriptionDisplaySku {
  const SubscriptionDisplaySku({
    required this.productId,
    required this.type,
    required this.copy,
    this.isDefault = false,
    this.weeklyReference = false,
    this.trial,
  });
  final String productId;
  final DisplayProductType type;
  final SubscriptionCopy copy;
  final bool isDefault, weeklyReference;
  final SubscriptionTrial? trial;
}

class SubscriptionDisplayConfig {
  SubscriptionDisplayConfig({
    required this.pageType,
    required List<SubscriptionDisplaySku> skus,
    this.configId,
    this.revision,
    this.trialEnabled = false,
    this.trialToggleText = '',
    this.cta = '',
    this.closeDelay = Duration.zero,
    this.isLocalFallback = false,
  }) : skus = List.unmodifiable(skus);
  final SubscriptionPageType pageType;
  final String? configId;
  final int? revision;
  final List<SubscriptionDisplaySku> skus;
  final bool trialEnabled;
  final String trialToggleText, cta;
  final Duration closeDelay;
  final bool isLocalFallback;

  Set<String> get productIds => {
    for (final sku in skus) ...{
      sku.productId,
      if (trialEnabled && sku.trial != null) sku.trial!.productId,
    },
  };

  factory SubscriptionDisplayConfig.fromJson(
    Object? value,
    SubscriptionPageType expectedType,
  ) {
    final json = _object(value);
    if (json['schema_version'] != 1 ||
        json['page_type'] != expectedType.name ||
        json['trial_enabled'] is! bool ||
        json['skus'] is! List) {
      throw const FormatException('Unsupported subscription configuration');
    }
    if ((json['skus'] as List).length > 3) {
      throw const FormatException('At most 3 display SKUs are allowed');
    }
    final delay = json['close_delay_seconds'];
    final revision = json['revision'];
    if (delay is! int ||
        delay < 0 ||
        delay > 9223372036854 ||
        revision is! int ||
        revision < 1) {
      throw const FormatException('Invalid configuration revision or delay');
    }
    final trialEnabled = json['trial_enabled'] == true;
    final ids = <String>{};
    final skus = <SubscriptionDisplaySku>[];
    for (final item in json['skus'] as List) {
      final sku = _object(item);
      final id = _productId(sku);
      final type = switch (sku['product_type']) {
        'subscription' => DisplayProductType.subscription,
        'non_consumable' => DisplayProductType.nonConsumable,
        _ => throw const FormatException('Unknown product type'),
      };
      final priceMode = sku['price_mode'];
      if (!ids.add(id) ||
          sku['is_default'] is! bool ||
          (priceMode != 'actual' && priceMode != 'weekly') ||
          (type == DisplayProductType.nonConsumable && priceMode != 'actual')) {
        throw const FormatException('Invalid display SKU');
      }
      SubscriptionTrial? trial;
      if (trialEnabled && sku['trial'] != null) {
        final target = _object(sku['trial']);
        final targetId = _productId(target);
        if (type != DisplayProductType.subscription || !ids.add(targetId)) {
          throw const FormatException('Invalid trial relationship');
        }
        trial = SubscriptionTrial(
          productId: targetId,
          copy: SubscriptionCopy.fromJson(target),
        );
      }
      skus.add(
        SubscriptionDisplaySku(
          productId: id,
          type: type,
          copy: SubscriptionCopy.fromJson(sku),
          isDefault: sku['is_default'] == true,
          weeklyReference: priceMode == 'weekly',
          trial: trial,
        ),
      );
    }
    if (skus.isEmpty ||
        skus.where((sku) => sku.isDefault).length != 1 ||
        (trialEnabled && !skus.any((sku) => sku.trial != null))) {
      throw const FormatException('Missing default or trial SKU');
    }
    return SubscriptionDisplayConfig(
      pageType: expectedType,
      skus: skus,
      configId: _text(json, 'config_id', 100, required: true),
      revision: revision,
      trialEnabled: trialEnabled,
      trialToggleText: _text(
        json,
        'trial_toggle_text',
        100,
        required: trialEnabled,
      ),
      cta: _cta(json),
      closeDelay: Duration(seconds: delay),
    );
  }
}

Map<String, Object?> _object(Object? value) {
  if (value is! Map) throw const FormatException('Expected an object');
  return Map<String, Object?>.from(value);
}

String _text(
  Map<String, Object?> json,
  String key,
  int max, {
  bool required = false,
}) {
  final value = json[key];
  if (value is! String ||
      value.length > max ||
      (required && value.trim().isEmpty)) {
    throw FormatException('Invalid $key');
  }
  return value;
}

String _productId(Map<String, Object?> json) {
  final id = _text(json, 'product_id', 255, required: true);
  if (id.trim() != id) throw const FormatException('Invalid Product ID');
  return id;
}

String _cta(Map<String, Object?> json) {
  final value = _text(json, 'cta', 100);
  if (value.contains('{') || value.contains('}')) {
    throw const FormatException('CTA must be plain text');
  }
  return value;
}

String _description(Map<String, Object?> json, String key, int max) {
  final value = _text(json, key, max);
  if (RegExp(r'{([^}]+)}').allMatches(value).any((m) => m[1] != 'price')) {
    throw FormatException('Unknown placeholder in $key');
  }
  return value;
}
