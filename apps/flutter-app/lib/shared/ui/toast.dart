import 'package:flutter/material.dart';

const genericFailureToastText = 'Something went wrong. Please try again.';
const networkFailureToastText =
    'No internet connection. Please check your network and try again.';
const kandoToastDuration = Duration(seconds: 2);

SnackBar buildKandoToast(String message) {
  return SnackBar(
    content: Text(message),
    duration: kandoToastDuration,
    behavior: SnackBarBehavior.floating,
  );
}

void showKandoToast(BuildContext context, {required String message}) {
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(buildKandoToast(message));
}

void showKandoFailureToast(BuildContext context) {
  showKandoToast(context, message: genericFailureToastText);
}

void showKandoNetworkToast(BuildContext context) {
  showKandoToast(context, message: networkFailureToastText);
}
