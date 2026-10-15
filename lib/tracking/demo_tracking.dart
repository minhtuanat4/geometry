import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Illustrative route around a GPS fix, not road routing.
List<LatLng> createDemoRoute(LatLng origin) {
  const distance = Distance();
  return List.unmodifiable([
    origin,
    distance.offset(origin, 150, 0),
    distance.offset(origin, 300, 0),
    distance.offset(origin, 400, 30),
    distance.offset(origin, 500, 60),
    distance.offset(origin, 650, 70),
    distance.offset(origin, 800, 80),
  ]);
}

LatLng interpolatePosition(LatLng from, LatLng to, double fraction) {
  final t = fraction.clamp(0.0, 1.0);
  return LatLng(
    from.latitude + (to.latitude - from.latitude) * t,
    from.longitude + (to.longitude - from.longitude) * t,
  );
}

/// One bounded source of simulated packets. No location permission or backend.
class DemoTracking extends ChangeNotifier {
  static const durationSeconds = 120;
  List<LatLng> _route = const [];
  List<LatLng> get route => _route;
  bool get ready => _route.isNotEmpty;

  /// Anchor once per session. Later GPS fixes must not reset the simulation.
  void initialize(LatLng origin) {
    if (ready) return;
    _route = createDemoRoute(origin);
    notifyListeners();
  }

  Timer? _timer;
  int _elapsed = 0;
  bool get running => _timer != null;
  bool get completed => _elapsed == durationSeconds;
  int get packets => _elapsed;
  int get remainingSeconds => durationSeconds - _elapsed;
  double get progress => _elapsed / durationSeconds;
  LatLng get position {
    if (!ready) throw StateError('Waiting for a device location');
    final segment = progress * (_route.length - 1);
    final index = segment.floor().clamp(0, _route.length - 2);
    return interpolatePosition(
      _route[index],
      _route[index + 1],
      segment - index,
    );
  }

  void start() {
    if (!ready || running || completed) return;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsed++;
      if (completed) {
        _timer?.cancel();
        _timer = null;
      }
      notifyListeners();
    });
    notifyListeners();
  }

  void pause() {
    _timer?.cancel();
    _timer = null;
    notifyListeners();
  }

  void restart() {
    _timer?.cancel();
    _timer = null;
    _elapsed = 0;
    start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
