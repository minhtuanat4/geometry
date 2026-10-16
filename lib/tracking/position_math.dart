import 'package:latlong2/latlong.dart';

/// Interpolation for rendering between real GPS fixes; never generates fixes.
LatLng interpolatePosition(LatLng from, LatLng to, double fraction) {
  final t = fraction.clamp(0.0, 1.0);
  return LatLng(
    from.latitude + (to.latitude - from.latitude) * t,
    from.longitude + (to.longitude - from.longitude) * t,
  );
}
