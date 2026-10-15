import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'transport_mode.dart';
import 'road_labels.dart';

enum RoutingPreference { shortest, mainRoads }

class RoadRoute {
  RoadRoute({
    required List<List<LatLng>> lines,
    required this.distanceMeters,
    this.mainRoadMeters = 0,
    this.classifiedRoadMeters = 0,
    List<RoadLabel> roadLabels = const [],
  }) : roadLabels = List.unmodifiable(roadLabels),
       lines = List.unmodifiable(
         lines.map((line) => List<LatLng>.unmodifiable(line)),
       );
  // Preserve geometry parts so gaps are not connected with invented segments.
  final List<List<LatLng>> lines;
  final List<RoadLabel> roadLabels;
  final double distanceMeters;
  final double mainRoadMeters;
  final double classifiedRoadMeters;

  /// A meter on smaller/unknown roads costs more than a meter on main roads.
  double mainRoadScore(double minorRoadPenalty) =>
      mainRoadMeters + (distanceMeters - mainRoadMeters) * minorRoadPenalty;
  double get kilometers => distanceMeters / 1000;
}

class RoutingException implements Exception {
  const RoutingException(this.message);
  final String message;
}

abstract interface class RoutingService {
  Future<RoadRoute> findRoute(
    LatLng from,
    LatLng to, {
    RoutingPreference preference = RoutingPreference.shortest,
    TransportMode? transportMode,
  });
  void close();
}

class GeoapifyRoutingService implements RoutingService {
  GeoapifyRoutingService({
    this.apiKey = const String.fromEnvironment('GEOAPIFY_API_KEY'),
    this.mode = const String.fromEnvironment(
      'ROUTING_MODE',
      defaultValue: 'motorcycle',
    ),
    this.minorRoadPenalty = 3,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final String mode;

  /// Increase to favor main roads more strongly. Must be finite and >= 1.
  final double minorRoadPenalty;
  static const mainRoadClasses = {'motorway', 'trunk', 'primary', 'secondary'};
  final http.Client _client;

  @override
  Future<RoadRoute> findRoute(
    LatLng from,
    LatLng to, {
    RoutingPreference preference = RoutingPreference.shortest,
    TransportMode? transportMode,
  }) async {
    if (preference == RoutingPreference.shortest) {
      return _request(
        from,
        to,
        type: 'short',
        roadDetails: true,
        transportMode: transportMode,
      );
    }
    if (!minorRoadPenalty.isFinite || minorRoadPenalty < 1) {
      throw ArgumentError.value(
        minorRoadPenalty,
        'minorRoadPenalty',
        'Must be finite and >= 1',
      );
    }
    // Compare actual road classes instead of assuming balanced means wide roads.
    final candidates = await Future.wait([
      _candidate(from, to, type: 'balanced', transportMode: transportMode),
      _candidate(from, to, type: 'short', transportMode: transportMode),
    ]);
    final routes = candidates.whereType<RoadRoute>().toList();
    if (routes.isEmpty) throw candidates.first as RoutingException;
    // Without road-class metadata, retain balanced as the documented approximation.
    if (routes.every((route) => route.classifiedRoadMeters == 0)) {
      return routes.first;
    }
    routes.sort((a, b) {
      final score = a
          .mainRoadScore(minorRoadPenalty)
          .compareTo(b.mainRoadScore(minorRoadPenalty));
      return score != 0 ? score : a.distanceMeters.compareTo(b.distanceMeters);
    });
    return routes.first;
  }

  Future<Object> _candidate(
    LatLng from,
    LatLng to, {
    required String type,
    TransportMode? transportMode,
  }) async {
    try {
      return await _request(
        from,
        to,
        type: type,
        roadDetails: true,
        transportMode: transportMode,
      );
    } catch (error) {
      return error is RoutingException
          ? error
          : const RoutingException(
              'Không thể tải tuyến đường. Kiểm tra kết nối và thử lại.',
            );
    }
  }

  Future<RoadRoute> _request(
    LatLng from,
    LatLng to, {
    required String type,
    bool roadDetails = false,
    TransportMode? transportMode,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw const RoutingException(
        'Chưa cấu hình GEOAPIFY_API_KEY để tìm đường.',
      );
    }
    final uri = Uri.https('api.geoapify.com', '/v1/routing', {
      'waypoints':
          '${from.latitude},${from.longitude}|${to.latitude},${to.longitude}',
      'mode': transportMode?.apiValue ?? mode,
      'type': type,
      if (roadDetails) 'details': 'route_details',
      'units': 'metric',
      'format': 'geojson',
      'apiKey': apiKey,
    });
    final response = await _client
        .get(uri)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const RoutingException(
        'Không thể xác thực Routing API. Kiểm tra API key.',
      );
    }
    if (response.statusCode == 429) {
      throw const RoutingException(
        'Đã vượt hạn mức tìm đường. Hãy thử lại sau.',
      );
    }
    if (response.statusCode == 400 || response.statusCode == 404) {
      throw const RoutingException(
        'Không tìm được tuyến phù hợp cho hai vị trí và phương tiện này.',
      );
    }
    if (response.statusCode != 200) {
      throw const RoutingException(
        'Dịch vụ tìm đường đang gặp lỗi. Hãy thử lại.',
      );
    }
    return parseRoute(jsonDecode(utf8.decode(response.bodyBytes)));
  }

  static RoadRoute parseRoute(dynamic data) {
    if (data is! Map ||
        data['features'] is! List ||
        (data['features'] as List).isEmpty) {
      throw const RoutingException('Không tìm được tuyến đường.');
    }
    final feature = (data['features'] as List).first;
    if (feature is! Map ||
        feature['geometry'] is! Map ||
        feature['properties'] is! Map) {
      throw const RoutingException('Dữ liệu tuyến đường không hợp lệ.');
    }
    final geometry = feature['geometry'] as Map;
    final distance = (feature['properties'] as Map)['distance'];
    final coordinates = geometry['coordinates'];
    if (distance is! num ||
        !distance.isFinite ||
        distance < 0 ||
        coordinates is! List) {
      throw const RoutingException('Dữ liệu tuyến đường không hợp lệ.');
    }
    final List parts;
    if (geometry['type'] == 'LineString') {
      parts = [coordinates];
    } else if (geometry['type'] == 'MultiLineString') {
      parts = coordinates;
    } else {
      throw const RoutingException('Định dạng tuyến đường không được hỗ trợ.');
    }
    final lines = <List<LatLng>>[];
    for (final part in parts) {
      if (part is! List || part.length < 2) {
        throw const RoutingException('Tuyến đường thiếu tọa độ.');
      }
      final points = <LatLng>[];
      for (final coordinate in part) {
        if (coordinate is! List || coordinate.length < 2) {
          throw const RoutingException('Tọa độ tuyến đường không hợp lệ.');
        }
        final lon = coordinate[0];
        final lat = coordinate[1];
        if (lat is! num ||
            lon is! num ||
            !lat.isFinite ||
            !lon.isFinite ||
            lat.abs() > 90 ||
            lon.abs() > 180) {
          throw const RoutingException('Tọa độ tuyến đường không hợp lệ.');
        }
        // GeoJSON uses [longitude, latitude]; Flutter uses LatLng(latitude, longitude).
        points.add(LatLng(lat.toDouble(), lon.toDouble()));
      }
      lines.add(points);
    }
    if (lines.isEmpty) {
      throw const RoutingException('Tuyến đường không có tọa độ.');
    }
    var mainRoadMeters = 0.0;
    var classifiedMeters = 0.0;
    final legs = (feature['properties'] as Map)['legs'];
    if (legs is List) {
      for (final leg in legs) {
        if (leg is! Map || leg['steps'] is! List) continue;
        for (final step in leg['steps'] as List) {
          if (step is! Map) continue;
          final length = step['distance'];
          final roadClass = step['road_class'];
          if (length is! num ||
              !length.isFinite ||
              length < 0 ||
              roadClass is! String) {
            continue;
          }
          classifiedMeters += length;
          if (mainRoadClasses.contains(roadClass)) mainRoadMeters += length;
        }
      }
    }
    return RoadRoute(
      lines: lines,
      distanceMeters: distance.toDouble(),
      mainRoadMeters: mainRoadMeters.clamp(0, distance.toDouble()),
      classifiedRoadMeters: classifiedMeters.clamp(0, distance.toDouble()),
      roadLabels: buildRoadLabels(legs, lines),
    );
  }

  @override
  void close() => _client.close();
}
