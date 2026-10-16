import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'routing_service.dart';
import 'route_progress.dart';
import 'transport_mode.dart';

class RouteState {
  const RouteState({
    this.route,
    this.loading = false,
    this.waitingForGps = false,
    this.error,
    this.remainingLines,
    this.driverPosition,
    this.offRoute = false,
  });
  final RoadRoute? route;
  final List<List<LatLng>>? remainingLines;
  final LatLng? driverPosition;
  final bool offRoute;
  List<List<LatLng>> get visibleLines =>
      remainingLines ?? route?.lines ?? const [];
  final bool loading;
  final bool waitingForGps;
  final String? error;
}

class RouteController extends ValueNotifier<RouteState> {
  RouteController({
    required this.service,
    this.rerouteDistanceMeters = 50,
    this.snapDistanceMeters = 35,
    this.minRequestInterval = const Duration(seconds: 10),
  }) : super(const RouteState());

  final RoutingService service;
  final double rerouteDistanceMeters;
  final double snapDistanceMeters;
  RouteProgress? _progress;
  double? _deviationMeters;
  bool _forceRetry = false;
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
      _progress = null;
      _deviationMeters = null;
      _forceRetry = false;
      _pending = false;
      value = RouteState(waitingForGps: to != null);
      return;
    }
    if (destinationChanged ||
        preferenceChanged ||
        modeChanged ||
        _requestedFrom == null) {
      _progress = null;
      _deviationMeters = null;
      _forceRetry = false;
      value = const RouteState();
      _fetch();
    } else {
      _updateProgress();
      if (!_forceRetry && !_movedEnough()) {
        _pending = false;
        return;
      }
      if (value.loading) {
        _pending = true;
        return;
      }
      if (_cooldown == null) {
        _fetch();
      } else {
        _pending = true;
      }
    }
  }

  void _updateProgress() {
    if (_from == null || _progress == null) return;
    final match = _progress!.update(
      _from!,
      snapDistanceMeters: snapDistanceMeters,
    );
    if (match == null) return;
    _deviationMeters = match.distanceMeters;
    value = RouteState(
      route: value.route,
      remainingLines: match.lines.isEmpty ? value.remainingLines : match.lines,
      driverPosition: match.position,
      offRoute: match.distanceMeters > snapDistanceMeters,
      loading: value.loading,
      error: value.error,
    );
  }

  bool _movedEnough() {
    if (_from == null || _requestedFrom == null) return false;
    if (_progress != null) {
      return (_deviationMeters ?? 0) >= rerouteDistanceMeters;
    }
    return const Distance(roundResult: false)(_requestedFrom!, _from!) >=
        rerouteDistanceMeters;
  }

  RouteState _retained({bool loading = false, String? error}) => RouteState(
    route: value.route,
    remainingLines: value.remainingLines,
    driverPosition: value.driverPosition,
    offRoute: value.offRoute,
    loading: loading,
    error: error,
  );

  void retry() {
    if (_from == null || _to == null || value.loading) return;
    if (_cooldown == null) {
      _fetch();
    } else {
      _pending = true;
      _forceRetry = true;
      value = _retained();
    }
  }

  Future<void> _fetch() async {
    final from = _from!;
    final to = _to!;
    final revision = ++_revision;
    _requestedFrom = from;
    _pending = false;
    _forceRetry = false;
    _cooldown?.cancel();
    _cooldown = Timer(minRequestInterval, () {
      _cooldown = null;
      if (_pending &&
          !_disposed &&
          _from != null &&
          _to != null &&
          !value.loading &&
          (_forceRetry || _movedEnough())) {
        _fetch();
      }
    });
    if (from == to) {
      value = RouteState(
        driverPosition: from,
        route: RoadRoute(
          lines: [
            [from, to],
          ],
          distanceMeters: 0,
        ),
      );
      _progress = RouteProgress(value.route!.lines);
      _deviationMeters = 0;
      return;
    }
    value = _retained(loading: true);
    try {
      final route = await service.findRoute(
        from,
        to,
        preference: _preference,
        transportMode: _transportMode,
      );
      if (_disposed || revision != _revision) return;
      _progress = RouteProgress(route.lines);
      value = RouteState(route: route);
      _updateProgress();
      if (_pending && _cooldown == null && _movedEnough()) _fetch();
    } catch (error) {
      if (_disposed || revision != _revision) return;
      value = _retained(
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
