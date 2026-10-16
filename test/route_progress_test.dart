import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_location/routing/route_progress.dart';

void main() {
  const a = LatLng(21, 105);
  const b = LatLng(21, 105.001);
  const c = LatLng(21.001, 105.001);
  test(
    'Snaps GPS noise and preserves intermediate vertices around a corner',
    () {
      final progress = RouteProgress([
        [a, b, c],
      ]);
      final match = progress.update(
        const LatLng(21.00002, 105.0005),
        snapDistanceMeters: 35,
      )!;
      expect(match.position.latitude, closeTo(21, 0.000001));
      expect(match.lines.first, [match.position, b, c]);
      final next = progress.update(
        const LatLng(21.0005, 105.00102),
        snapDistanceMeters: 35,
      )!;
      expect(next.lines.first, [next.position, c]);
      expect(next.position.longitude, closeTo(105.001, 0.000001));
      final jitter = progress.update(
        const LatLng(21.00049, 105.001),
        snapDistanceMeters: 35,
      )!;
      expect(
        jitter.position.latitude,
        greaterThanOrEqualTo(next.position.latitude),
      );
    },
  );
  test('Off-route GPS does not consume route points or join geometry gaps', () {
    final progress = RouteProgress([
      [a, b],
      [const LatLng(21.002, 105.002), c],
    ]);
    final off = progress.update(
      const LatLng(21.01, 105),
      snapDistanceMeters: 35,
    )!;
    expect(off.lines, isEmpty);
    expect(off.position, const LatLng(21.01, 105));
    final back = progress.update(a, snapDistanceMeters: 35)!;
    expect(back.lines.length, 2);
    expect(back.lines.first, [a, b]);
  });
}
