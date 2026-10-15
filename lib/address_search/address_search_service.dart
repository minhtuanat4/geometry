import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

class AddressSuggestion {
  const AddressSuggestion({
    required this.id,
    required this.label,
    required this.position,
  });
  final String id;
  final String label;
  final LatLng position;
}

class AddressSearchException implements Exception {
  const AddressSearchException(this.message);
  final String message;
}

abstract interface class AddressSearchService {
  Future<List<AddressSuggestion>> search(String query, {LatLng? near});
  void close();
}

class GeoapifyAddressSearch implements AddressSearchService {
  GeoapifyAddressSearch({
    this.apiKey = const String.fromEnvironment('GEOAPIFY_API_KEY'),
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String apiKey;
  final http.Client _client;

  @override
  Future<List<AddressSuggestion>> search(String query, {LatLng? near}) async {
    if (apiKey.trim().isEmpty) {
      throw const AddressSearchException(
        'Tìm kiếm chưa được cấu hình. Vui lòng thêm GEOAPIFY_API_KEY khi chạy ứng dụng.',
      );
    }
    final uri = Uri.https('api.geoapify.com', '/v1/geocode/autocomplete', {
      'text': query.trim(),
      'apiKey': apiKey,
      'format': 'json',
      'lang': 'vi',
      'filter': 'countrycode:vn',
      'limit': '5',
      if (near != null) 'bias': 'proximity:${near.longitude},${near.latitude}',
    });
    final response = await _client.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const AddressSearchException(
        'Không thể xác thực dịch vụ địa chỉ. Vui lòng kiểm tra API key.',
      );
    }
    if (response.statusCode == 429) {
      throw const AddressSearchException(
        'Đã vượt hạn mức tìm kiếm. Vui lòng thử lại sau.',
      );
    }
    if (response.statusCode != 200) {
      throw const AddressSearchException(
        'Dịch vụ địa chỉ đang gặp lỗi. Vui lòng thử lại.',
      );
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! Map<String, dynamic> || data['results'] is! List) {
      throw const AddressSearchException(
        'Dữ liệu địa chỉ không hợp lệ. Vui lòng thử lại.',
      );
    }
    final seen = <String>{};
    final suggestions = <AddressSuggestion>[];
    for (final item in data['results'] as List) {
      if (item is! Map<String, dynamic>) continue;
      final lat = item['lat'];
      final lon = item['lon'];
      final label = item['formatted'];
      if (lat is! num ||
          lon is! num ||
          label is! String ||
          label.trim().isEmpty ||
          !lat.isFinite ||
          !lon.isFinite ||
          lat.abs() > 90 ||
          lon.abs() > 180) {
        continue;
      }
      final id = item['place_id']?.toString() ?? '$label:$lat:$lon';
      if (!seen.add(id)) continue;
      suggestions.add(
        AddressSuggestion(
          id: id,
          label: label,
          position: LatLng(lat.toDouble(), lon.toDouble()),
        ),
      );
    }
    return List.unmodifiable(suggestions);
  }

  @override
  void close() => _client.close();
}
