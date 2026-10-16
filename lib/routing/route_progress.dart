import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

class RouteMatch {
  const RouteMatch(this.position, this.distanceMeters, this.lines);
  final LatLng position;
  final double distanceMeters;
  final List<List<LatLng>> lines;
}

/// Projects GPS onto remaining segments, preserving multipart geometry.
/// The cursor only advances after an accepted on-route fix.
class RouteProgress {
  RouteProgress(this.lines);
  final List<List<LatLng>> lines;
  int _line = 0;
  int _segment = 0;
  double _fraction = 0;

  RouteMatch? update(LatLng gps, {required double snapDistanceMeters}) {
    double bestDistance = double.infinity;
    LatLng? best;
    int bestLine = _line;
    int bestSegment = _segment;
    double bestFraction = _fraction;
    const distance = Distance(roundResult: false);
    for (var l = _line; l < lines.length; l++) {
      for (var s = l == _line ? _segment : 0; s + 1 < lines[l].length; s++) {
        final a = lines[l][s];
        final b = lines[l][s + 1];
        // Local equirectangular projection; route segments are short road edges.
        final scale = math.cos(gps.latitude * math.pi / 180);
        final ax = (a.longitude - gps.longitude) * scale;
        final ay = a.latitude - gps.latitude;
        final bx = (b.longitude - gps.longitude) * scale;
        final by = b.latitude - gps.latitude;
        final dx = bx - ax;
        final dy = by - ay;
        final lengthSquared = dx * dx + dy * dy;
        final minimum = l == _line && s == _segment ? _fraction : 0.0;
        final t =
            (lengthSquared == 0 ? 0.0 : -(ax * dx + ay * dy) / lengthSquared)
                .clamp(minimum, 1.0);
        final point = LatLng(
          a.latitude + (b.latitude - a.latitude) * t,
          a.longitude + (b.longitude - a.longitude) * t,
        );
        final meters = distance(gps, point);
        // Prefer earlier progress for near-equal matches at intersections.
        if (meters + 1 < bestDistance) {
          bestDistance = meters;
          best = point;
          bestLine = l;
          bestSegment = s;
          bestFraction = t;
        }
      }
    }
    if (best == null) return null;
    if (bestDistance > snapDistanceMeters) {
      return RouteMatch(gps, bestDistance, const []);
    }
    _line = bestLine;
    _segment = bestSegment;
    _fraction = bestFraction;
    return RouteMatch(
      best,
      bestDistance,
      List.unmodifiable([
        List<LatLng>.unmodifiable([best, ...lines[_line].skip(_segment + 1)]),
        ...lines.skip(_line + 1),
      ]),
    );
  }
}
