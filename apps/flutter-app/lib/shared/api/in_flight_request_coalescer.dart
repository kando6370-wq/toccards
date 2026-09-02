import 'dart:async';

class InFlightRequestCoalescer {
  final Map<String, Future<Object?>> _requests = {};

  Future<T> run<T>(String key, Future<T> Function() request) {
    final existing = _requests[key];
    if (existing != null) return existing as Future<T>;

    late final Future<T> future;
    future = Future<T>.sync(request).whenComplete(() {
      if (identical(_requests[key], future)) _requests.remove(key);
    });
    _requests[key] = future;
    return future;
  }
}
