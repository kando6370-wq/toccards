import 'package:kando_app/shared/portfolio/portfolio_providers.dart';

class InMemoryPortfolioAmountHiddenStorage
    implements PortfolioAmountHiddenStorage {
  InMemoryPortfolioAmountHiddenStorage({this.value = false, this.fail = false});

  bool value;
  bool fail;
  final List<bool> writes = [];

  @override
  Future<bool> readAmountHidden() async => value;

  @override
  Future<void> writeAmountHidden(bool amountHidden) async {
    if (fail) throw StateError('Local amount visibility storage unavailable.');
    value = amountHidden;
    writes.add(amountHidden);
  }
}
