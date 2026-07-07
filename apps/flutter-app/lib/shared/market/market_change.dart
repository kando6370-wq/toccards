class MarketChange {
  const MarketChange._({
    required this.currentValue,
    required this.amount,
    required this.percent,
  });

  factory MarketChange.fromPrices({
    required double? current,
    required double? previous,
    int quantity = 1,
  }) {
    final normalizedQuantity = quantity < 1 ? 1 : quantity;
    final validCurrent = _isValidPrice(current);
    final validPrevious = _isValidPrice(previous);

    final currentValue = validCurrent ? current! * normalizedQuantity : null;
    final amount = validCurrent && validPrevious
        ? (current! - previous!) * normalizedQuantity
        : null;
    final percent = validCurrent && validPrevious
        ? (current! - previous!) / previous! * 100
        : null;

    return MarketChange._(
      currentValue: currentValue,
      amount: amount,
      percent: percent,
    );
  }

  final double? currentValue;
  final double? amount;
  final double? percent;

  String get currentValueText => _formatMoney(currentValue);

  String get amountText => _formatMoney(amount);

  String get percentText => _formatPercent(percent);

  static bool _isValidPrice(double? value) {
    return value != null && value > 0;
  }

  static String _formatMoney(double? value) {
    if (value == null) {
      return '--';
    }

    final sign = value < 0 ? '-' : '';
    return '$sign\$${value.abs().toStringAsFixed(2)}';
  }

  static String _formatPercent(double? value) {
    if (value == null) {
      return '-/-';
    }

    if (value != 0 && value.abs() < 0.01) {
      return value < 0 ? '-<0.01%' : '<0.01%';
    }

    final sign = value > 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(2)}%';
  }
}
