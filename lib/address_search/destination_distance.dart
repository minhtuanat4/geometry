import 'package:latlong2/latlong.dart';

/// Direct surface distance between GPS and the selected address, not road length.
class DestinationDistance {
  DestinationDistance({required this.devicePosition, required this.destination})
    : kilometers = const Distance(
        roundResult: false,
      ).as(LengthUnit.Kilometer, devicePosition, destination);

  final LatLng devicePosition;
  final LatLng destination;
  final double kilometers;
}
