import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_location/tracking/heading_math.dart';

void main() {
  test('Compass crosses north in the shortest direction', () {
    expect(headingDelta(359, 1), 2);
    expect(headingDelta(1, 359), -2);
    expect(headingDelta(719, 1), 2);
    expect(headingDelta(-1, 1), 2);
    expect(headingRadians(90), closeTo(math.pi / 2, 0.00001));
  });
}
