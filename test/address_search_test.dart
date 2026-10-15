import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_location/address_search/address_search_controller.dart';
import 'package:flutter_location/address_search/address_search_service.dart';

class PendingAddressSearch implements AddressSearchService {
  final requests = <String, Completer<List<AddressSuggestion>>>{};
  @override
  Future<List<AddressSuggestion>> search(String query, {LatLng? near}) =>
      (requests[query] = Completer<List<AddressSuggestion>>()).future;
  @override
  void close() {}
}

void main() {
  test(
    'Autocomplete sends encoded input and correct longitude-latitude bias',
    () async {
      final service = GeoapifyAddressSearch(
        apiKey: 'test-key',
        client: MockClient((request) async {
          expect(request.url.queryParameters['text'], 'Nguyễn Huệ & Q1');
          expect(
            request.url.queryParameters['bias'],
            'proximity:105.8542,21.0285',
          );
          expect(request.url.queryParameters['filter'], 'countrycode:vn');
          return http.Response(
            jsonEncode({
              'results': [
                {
                  'place_id': '1',
                  'formatted': 'Địa chỉ mẫu',
                  'lat': 21.03,
                  'lon': 105.85,
                },
                {
                  'place_id': '1',
                  'formatted': 'Trùng',
                  'lat': 21.03,
                  'lon': 105.85,
                },
                {'formatted': 'Sai tọa độ', 'lat': 999, 'lon': 105},
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final results = await service.search(
        'Nguyễn Huệ & Q1',
        near: const LatLng(21.0285, 105.8542),
      );
      expect(results.single.label, 'Địa chỉ mẫu');
      expect(results.single.position, const LatLng(21.03, 105.85));
      service.close();
    },
  );

  test('Missing key and quota errors are actionable', () async {
    final missing = GeoapifyAddressSearch(apiKey: '');
    await expectLater(
      missing.search('Hà Nội'),
      throwsA(isA<AddressSearchException>()),
    );
    missing.close();
    final limited = GeoapifyAddressSearch(
      apiKey: 'test-key',
      client: MockClient((_) async => http.Response('', 429)),
    );
    await expectLater(
      limited.search('Hà Nội'),
      throwsA(
        isA<AddressSearchException>().having(
          (e) => e.message,
          'message',
          contains('hạn mức'),
        ),
      ),
    );
    limited.close();
  });

  testWidgets(
    'Debounces typing and ignores stale responses, clearing and disposal',
    (tester) async {
      final service = PendingAddressSearch();
      final controller = AddressSearchController(service: service);
      controller.queryChanged('Hà');
      await tester.pump(const Duration(milliseconds: 500));
      expect(service.requests, isEmpty);
      controller.queryChanged('Hà N');
      await tester.pump(const Duration(milliseconds: 200));
      controller.queryChanged('Hà Nội');
      await tester.pump(const Duration(milliseconds: 399));
      expect(service.requests, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      expect(service.requests.keys, ['Hà Nội']);
      controller.queryChanged('Đà Nẵng');
      await tester.pump(const Duration(milliseconds: 400));
      const result = AddressSuggestion(
        id: 'dn',
        label: 'Đà Nẵng',
        position: LatLng(16.05, 108.2),
      );
      service.requests['Đà Nẵng']!.complete([result]);
      await tester.pump();
      service.requests['Hà Nội']!.complete([]);
      await tester.pump();
      expect(controller.value.results.single.label, 'Đà Nẵng');
      controller.queryChanged('Hà Nội lần 2');
      await tester.pump(const Duration(milliseconds: 400));
      controller.queryChanged('');
      service.requests['Hà Nội lần 2']!.complete([result]);
      await tester.pump();
      expect(controller.value.results, isEmpty);
      controller.queryChanged('Huế');
      await tester.pump(const Duration(milliseconds: 400));
      controller.dispose();
      service.requests['Huế']!.complete([result]);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
