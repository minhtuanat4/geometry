import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_location/tracking/heading_filter.dart';

void main() {
  test('Ignores noise up to 10 degrees against the last accepted heading', () {
    final filter = HeadingFilter(
      const HeadingSettings(
        angularThresholdDegrees: 10,
        minUpdateInterval: Duration(milliseconds: 600),
        animationDuration: Duration(milliseconds: 500),
      ),
    );
    expect(filter.accept(0, Duration.zero), 0);
    expect(filter.accept(6, const Duration(milliseconds: 600)), isNull);
    expect(filter.accept(10, const Duration(milliseconds: 700)), isNull);
    expect(filter.accept(11, const Duration(milliseconds: 800)), 11);
    expect(filter.accept(21, const Duration(milliseconds: 1400)), isNull);
    expect(filter.accept(22, const Duration(milliseconds: 1500)), 22);
  });

  test('Throttles updates and unwraps the shortest turn across north', () {
    final filter = HeadingFilter(
      const HeadingSettings(
        angularThresholdDegrees: 10,
        minUpdateInterval: Duration(milliseconds: 600),
        animationDuration: Duration(milliseconds: 500),
      ),
    );
    expect(filter.accept(355, Duration.zero), 355);
    expect(filter.accept(20, const Duration(milliseconds: 599)), isNull);
    expect(filter.accept(5, const Duration(milliseconds: 600)), isNull);
    expect(filter.accept(6, const Duration(milliseconds: 601)), 366);
    expect(filter.accept(350, const Duration(milliseconds: 1201)), 350);
    filter.reset();
    expect(filter.accept(90, const Duration(milliseconds: 1202)), 90);
  });

  test('Allows a custom threshold and update interval', () {
    final filter = HeadingFilter(
      const HeadingSettings(
        angularThresholdDegrees: 20,
        minUpdateInterval: Duration(seconds: 1),
        animationDuration: Duration(milliseconds: 800),
      ),
    );
    expect(filter.accept(0, Duration.zero), 0);
    expect(filter.accept(30, const Duration(milliseconds: 999)), isNull);
    expect(filter.accept(20, const Duration(seconds: 1)), isNull);
    expect(filter.accept(21, const Duration(seconds: 1)), 21);
  });
}
