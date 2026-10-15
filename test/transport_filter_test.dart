import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_location/address_search/address_search_service.dart';
import 'package:flutter_location/address_search/address_search_sheet.dart';
import 'package:flutter_location/routing/transport_mode.dart';

class EmptySearch implements AddressSearchService {
  @override
  Future<List<AddressSuggestion>> search(String query, {LatLng? near}) async =>
      [];
  @override
  void close() {}
}

void main() {
  testWidgets(
    'Transport filter remains usable on a phone with the keyboard open',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetViewInsets);
      final mode = ValueNotifier(TransportMode.motorcycle);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AddressSearchSheet(
              service: EmptySearch(),
              transportMode: mode,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bus = find.byKey(const ValueKey('transport-mode-bus'));
      await tester.ensureVisible(bus);
      await tester.tap(bus);
      await tester.pump();
      expect(mode.value, TransportMode.bus);
      expect(tester.widget<ChoiceChip>(bus).selected, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      mode.dispose();
    },
  );
}
