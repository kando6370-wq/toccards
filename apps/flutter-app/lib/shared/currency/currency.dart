import 'package:flutter_riverpod/flutter_riverpod.dart';

const hiddenMoneyText = '••••••';

class AppCurrency {
  const AppCurrency._(this.code, this.label, this.symbol, this.usdRate);

  static const usd = AppCurrency._('USD', 'US Dollar', r'$', 1);
  static const eur = AppCurrency._('EUR', 'Euro', '€', null);
  static const jpy = AppCurrency._('JPY', 'Japanese Yen', '¥', null);
  static const gbp = AppCurrency._('GBP', 'British Pound', '£', null);
  static const cad = AppCurrency._('CAD', 'Canadian Dollar', r'C$', null);
  static const aud = AppCurrency._('AUD', 'Australian Dollar', r'A$', null);
  static const nzd = AppCurrency._('NZD', 'New Zealand Dollar', r'NZ$', null);
  static const sgd = AppCurrency._('SGD', 'Singapore Dollar', r'S$', null);

  static const values = [usd, eur, jpy, gbp, cad, aud, nzd, sgd];

  final String code;
  final String label;
  final String symbol;
  final double? usdRate;

  AppCurrency withUsdRate(double rate) {
    return AppCurrency._(code, label, symbol, rate);
  }

  static AppCurrency fromCode(String code) {
    return AppCurrency.values.firstWhere(
      (currency) => currency.code == code,
      orElse: () => AppCurrency.usd,
    );
  }
}

class CurrencyFormatter {
  const CurrencyFormatter({required this.currency});

  final AppCurrency currency;

  String formatUsd(
    double? valueUsd, {
    int quantity = 1,
    bool hidden = false,
    bool allowZero = true,
  }) {
    if (hidden) {
      return hiddenMoneyText;
    }
    if (valueUsd == null || (!allowZero && valueUsd <= 0)) {
      return '--';
    }

    final normalizedQuantity = quantity < 1 ? 1 : quantity;
    final rate = currency.usdRate;
    if (rate == null) {
      return '--';
    }
    final converted = valueUsd * normalizedQuantity * rate;
    return _format(converted);
  }

  String _format(double value) {
    final sign = value < 0 ? '-' : '';
    final fixed = value.abs().toStringAsFixed(2);
    final parts = fixed.split('.');
    return '$sign${currency.symbol}${_withThousands(parts[0])}.${parts[1]}';
  }

  String _withThousands(String value) {
    final buffer = StringBuffer();
    for (var index = 0; index < value.length; index++) {
      final remaining = value.length - index;
      buffer.write(value[index]);
      if (remaining > 1 && remaining % 3 == 1) {
        buffer.write(',');
      }
    }
    return buffer.toString();
  }
}

final selectedCurrencyProvider =
    NotifierProvider<SelectedCurrencyController, AppCurrency>(
      SelectedCurrencyController.new,
    );

class SelectedCurrencyController extends Notifier<AppCurrency> {
  @override
  AppCurrency build() {
    return AppCurrency.usd;
  }

  void select(AppCurrency currency) {
    state = currency;
  }
}
