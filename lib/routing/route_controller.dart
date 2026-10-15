import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'routing_service.dart';
import 'transport_mode.dart';

class RouteState {
  const RouteState({
    this.route,
    this.loading = false,
    this.waitingForGps = false,
    this.error,
  });
  final RoadRoute? route;
  final bool loading;
  final bool waitingForGps;
  final String? error;
}

class RouteController extends ValueNotifier<RouteState> {
  RouteController({
    required this.service,
    this.rerouteDistanceMeters = 50,
    this.minRequestInterval = const Duration(seconds: 10),
  }) : super(const RouteState());

  final RoutingService service;
  final double rerouteDistanceMeters;
  final Duration minRequestInterval;
  RoutingPreference _preference = RoutingPreference.shortest;
  RoutingPreference get preference => _preference;
  TransportMode? _transportMode;
  LatLng? _from;
  LatLng? _to;
  LatLng? _requestedFrom;
  Timer? _cooldown;
  bool _pending = false;
  bool _disposed = false;
  int _revision = 0;

  /// Keep this entry point for the shortest-distance choice.
  void update({
    required LatLng? from,
    required LatLng? to,
    TransportMode? transportMode,
  }) => _update(
    from: from,
    to: to,
    preference: RoutingPreference.shortest,
    transportMode: transportMode,
  );

  /// Walking uses the shortest walkable route instead of favoring large roads.
  void updatePreferMainRoads({
    required LatLng? from,
    required LatLng? to,
    TransportMode? transportMode,
  }) => _update(
    from: from,
    to: to,
    preference: transportMode == TransportMode.walking
        ? RoutingPreference.shortest
        : RoutingPreference.mainRoads,
    transportMode: transportMode,
  );

  void _update({
    required LatLng? from,
    required LatLng? to,
    required RoutingPreference preference,
    TransportMode? transportMode,
  }) {
    final modeChanged = _transportMode != transportMode;
    _transportMode = transportMode;
    final preferenceChanged = _preference != preference;
    _preference = preference;
    final destinationChanged = _to != to;
    _from = from;
    _to = to;
    if (from == null || to == null) {
      _revision++;
      _cooldown?.cancel();
      _cooldown = null;
      _requestedFrom = null;
      _pending = false;
      value = RouteState(waitingForGps: to != null);
      return;
    }
    if (destinationChanged ||
        preferenceChanged ||
        modeChanged ||
        _requestedFrom == null) {
      _fetch();
    } else if (value.error == null && _movedEnough()) {
      if (_cooldown == null) {
        _fetch();
      } else {
        _pending = true;
      }
    }
  }

  bool _movedEnough() =>
      _from != null &&
      _requestedFrom != null &&
      const Distance(roundResult: false)(_requestedFrom!, _from!) >=
          rerouteDistanceMeters;

  void retry() {
    if (_from == null || _to == null || value.loading) return;
    if (_cooldown == null) {
      _fetch();
    } else {
      _pending = true;
      value = const RouteState(loading: true);
    }
  }

  Future<void> _fetch() async {
    final from = _from!;
    final to = _to!;
    final revision = ++_revision;
    _requestedFrom = from;
    _pending = false;
    _cooldown?.cancel();
    _cooldown = Timer(minRequestInterval, () {
      _cooldown = null;
      if (_pending && !_disposed && _from != null && _to != null) _fetch();
    });
    if (from == to) {
      value = RouteState(
        route: RoadRoute(
          lines: [
            [from, to],
          ],
          distanceMeters: 0,
        ),
      );
      return;
    }
    value = const RouteState(loading: true);
    try {
      final route = await service.findRoute(
        from,
        to,
        preference: _preference,
        transportMode: _transportMode,
      );
      if (_disposed || revision != _revision) return;
      value = RouteState(route: route);
    } catch (error) {
      if (_disposed || revision != _revision) return;
      value = RouteState(
        error: error is RoutingException
            ? error.message
            : 'Không thể tải tuyến đường. Kiểm tra kết nối và thử lại.',
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _cooldown?.cancel();
    super.dispose();
  }
}
