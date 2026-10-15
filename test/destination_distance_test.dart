import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_location/address_search/destination_distance.dart';

void main() {
  test(
    'Reports kilometers including fractional values and coincident points',
    () {
      final oneDegree = DestinationDistance(
        devicePosition: const LatLng(0, 0),
        destination: const LatLng(0, 1),
      );
      expect(oneDegree.kilometers, closeTo(111.3195, 0.001));
      final nearby = DestinationDistance(
        devicePosition: const LatLng(0, 0),
        destination: const LatLng(0, .001),
      );
      expect(nearby.kilometers, closeTo(.1113195, .000001));
      final same = DestinationDistance(
        devicePosition: const LatLng(21, 105),
        destination: const LatLng(21, 105),
      );
      expect(same.kilometers, 0);
    },
  );
}
