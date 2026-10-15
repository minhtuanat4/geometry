# Từ hai điểm đến tuyến bám theo đường

Luồng đã triển khai:

```text
GPS thiết bị + tọa độ địa chỉ đã chọn
                 ↓
Geoapify Routing API (balanced + short, mode=motorcycle)
                 ↓
Chấm điểm theo road_class để ưu tiên đường chính
                 ↓
GeoJSON geometry + chiều dài tuyến
                 ↓
[lon, lat] → LatLng(lat, lon)
                 ↓
ValueNotifier<RouteState> → PolylineLayer màu _green
```

Bản đồ nền là các ảnh tile, không có đủ thông tin để tìm đường trong Flutter. Routing engine dùng dữ liệu mạng đường: các giao lộ/kết nối, đoạn đường và điều kiện phương tiện. Yêu cầu `type=short` tối ưu chiều dài theo dữ liệu mạng đường của provider. Kết quả phụ thuộc độ đầy đủ/cập nhật của bản đồ và loại phương tiện, không bảo đảm mọi lối đi ngoài thực tế đều có trong dữ liệu. Tuyến ngắn theo km có thể mất nhiều thời gian hơn một tuyến khác.

Tài liệu chính thức: [Geoapify Routing API](https://apidocs.geoapify.com/docs/routing/).

## Hai hàm update trong RouteController

Ứng dụng hiện gọi hàm mới:

```dart
_route.updatePreferMainRoads(from: devicePosition, to: destination);
```

Hàm cũ vẫn giữ cho lựa chọn ngắn theo km:

```dart
_route.update(from: devicePosition, to: destination);
```

Đổi hàm với cùng hai tọa độ vẫn tính lại ngay, loại phản hồi cũ; các lần cập nhật GPS và retry sau đó giữ lựa chọn đã dùng. UI hiện nhãn “Ưu tiên đường chính” cho hàm mới. Lớp tìm kiếm có thanh chọn phương tiện; đổi phương tiện sẽ tính lại tuyến đang chọn ngay và giữ lựa chọn khi mở lại lớp tìm kiếm.

### Bộ lọc phương tiện

| Bộ lọc | Mode API | Cách tính mặc định |
| --- | --- | --- |
| Xe máy | motorcycle | Ưu tiên đường chính |
| Ô tô | drive | Ưu tiên đường chính |
| Đi bộ | walk | Tuyến đi bộ ngắn, không tăng ưu tiên đường lớn |
| Xe bus | bus | Ưu tiên đường chính theo profile xe bus |

Thanh chọn nằm trong AddressSearchSheet, dùng ValueNotifier<TransportMode>. Trạng thái lựa chọn thuộc TrackingPage; địa chỉ autocomplete không bị thay đổi hoặc gọi lại chỉ vì đổi phương tiện. RouteController nhận transportMode ở cả update() và updatePreferMainRoads(); đổi mode là điều kiện tính lại ngay, phản hồi mode cũ bị bỏ qua. Retry và cập nhật GPS giữ nguyên mode hiện hành. Nếu không truyền transportMode, service vẫn dùng ROUTING_MODE như trước. Trên UI, ROUTING_MODE chỉ làm lựa chọn ban đầu, người dùng có thể đổi lại.

Xe bus hiện sử dụng đường dành cho phương tiện bus, không phải tìm số tuyến, điểm chuyển tuyến hoặc lịch xe bus công cộng. UI ghi rõ giới hạn này. Muốn hỗ trợ hành khách đi bus cần luồng public transit riêng. Bốn profile tương ứng theo [tài liệu Routing API](https://apidocs.geoapify.com/docs/routing/).

### Cách ưu tiên đường chính

Geoapify không cung cấp tham số trực tiếp theo chiều rộng đường trong API hiện tại. Hàm mới lấy hai ứng viên `balanced` và `short`, có `details=route_details`. Parser cộng `steps[].distance` theo `steps[].road_class`. Các lớp đường chính trong code: `motorway`, `trunk`, `primary`, `secondary`; provider vẫn tính theo `ROUTING_MODE` đang chọn.

Hàm chấm điểm:

```text
score = mét đường chính + mét đường nhỏ/không rõ × minorRoadPenalty
```

Chọn ứng viên có score thấp nhất; nếu bằng nhau, chọn tuyến ngắn hơn. Mặc định `minorRoadPenalty=3`: một mét đường nhỏ có chi phí gấp ba một mét đường chính. Ví dụ tuyến 1.8km gồm 1.5km đường chính + 0.3km đường nhỏ có score 2400, được ưu tiên hơn tuyến 1km toàn đường nhỏ có score 3000. Đây là lựa chọn giữa hai ứng viên, không phải tìm mọi tuyến có thể có hoặc đo chiều rộng/số làn thực tế.

Chỉnh hệ số khi tạo service:

```dart
GeoapifyRoutingService(minorRoadPenalty: 4)
```

Có thể chỉnh tập `GeoapifyRoutingService.mainRoadClasses` trong code. Khi cả hai ứng viên thiếu phân loại đường, giữ `balanced` làm phương án gần đúng; nếu một request lỗi, dùng ứng viên hợp lệ còn lại; nếu cả hai lỗi, hiện lỗi. Hàm mới dùng **hai request cho mỗi lượt tính tuyến**, kèm chi tiết đường; cần tính phần này vào quota/chi phí provider. Hàm `update()` vẫn chỉ dùng một request `short`, hiện cũng yêu cầu `route_details` để có tên đường.

## Chạy

Dùng cùng key đã cấu hình cho tìm địa chỉ:

```sh
flutter run --dart-define=GEOAPIFY_API_KEY=YOUR_KEY
```

Mặc định chọn `motorcycle`. Có thể cấu hình theo phương tiện thực tế, ví dụ:

```sh
flutter run --dart-define=GEOAPIFY_API_KEY=YOUR_KEY --dart-define=ROUTING_MODE=drive
```

Chọn điểm đến từ danh sách địa chỉ; app tự lấy GPS làm điểm xuất phát và gọi API. Khi chưa cấu hình key, không tìm được đường hoặc API lỗi, app báo lỗi và có nút thử lại. Không tự tạo tuyến thẳng thay thế. Chưa kiểm tra với key và mạng thật.

## 1. Gửi hai điểm để tìm đường

Mã trong `lib/routing/routing_service.dart`, phương thức `findRoute()`:

```dart
final uri = Uri.https('api.geoapify.com', '/v1/routing', {
  'waypoints': '${from.latitude},${from.longitude}|${to.latitude},${to.longitude}',
  'mode': 'motorcycle',
  'type': 'short',
  'units': 'metric',
  'format': 'geojson',
  'apiKey': apiKey,
});
```

`waypoints` dùng `lat,lon`; provider trả geometry GeoJSON theo thứ tự `lon,lat`. Không thêm tất cả các giao lộ làm waypoint: hai điểm là đủ để server tìm tuyến và trả các điểm trung gian.

## 2. Đọc các điểm dọc tuyến

Ví dụ cấu trúc minh họa, không phải tuyến thực được xác minh:

```json
{
  "features": [{
    "properties": { "distance": 1800, "distance_units": "Meters" },
    "geometry": {
      "type": "MultiLineString",
      "coordinates": [
        [[105.85, 21.03], [105.86, 21.03], [105.86, 21.04]]
      ]
    }
  }]
}
```

Mỗi phần trong `coordinates` là một đường gồm các điểm theo thứ tự di chuyển. Parser `GeoapifyRoutingService.parseRoute()` đọc LineString hoặc MultiLineString, kiểm tra tọa độ, giữ từng phần riêng. Chuyển từng cặp:

```dart
final point = LatLng(coordinate[1], coordinate[0]);
```

Geometry có thể bắt đầu/kết thúc tại vị trí đã được gắn vào mạng đường, hơi khác GPS hoặc tâm địa chỉ. Không tự chèn đường thẳng từ GPS tới mạng đường rồi coi đó là đường đi hợp lệ.

## 3. Vẽ và hiển thị km

`RoadRoute.lines` giữ danh sách tọa độ của từng phần, main.dart lắng nghe `_route` để vẽ:

```dart
PolylineLayer(
  polylines: [
    for (final points in state.route?.lines ?? <List<LatLng>>[])
      Polyline(points: points, color: _green, strokeWidth: 5),
  ],
)
```

Với request metric, `properties.distance` là chiều dài toàn tuyến theo mét; chia 1000 để lấy km. UI hiển thị chiều dài của tuyến được tính gần nhất, không gọi đó là khoảng cách còn lại chính xác theo từng mét di chuyển.

## 4. GPS realtime và hiệu năng

`lib/routing/route_controller.dart` giữ state bằng ValueNotifier. Chỉ phần polyline và trạng thái tuyến lắng nghe nó; camera/marker vẫn có cơ chế riêng.

- Chọn/đổi điểm đến: tính tuyến ngay.
- GPS đổi: tính lại khi cách vị trí dùng cho lần gọi trước ít nhất 50m; cách nhau tối thiểu 10 giây cho cập nhật GPS. Đây là quy tắc theo độ dịch chuyển, chưa phải phát hiện lệch tuyến.
- Trong thời gian chờ, gom vị trí mới; đến lượt thì dùng GPS gần nhất. Không gọi theo từng frame hoặc sự kiện la bàn.
- Đổi điểm đến, mất GPS, xóa điểm đến hoặc dispose: phản hồi cũ bị bỏ qua; không ghi đè tuyến mới. Request đã gửi không được hủy vật lý.
- Mất GPS: ẩn tuyến và báo chờ; có GPS lại thì tính mới. Khi lỗi cần bấm thử lại, không tự lặp liên tục. Nút thử lại cũng chờ hết chu kỳ 10 giây nếu còn cooldown.
- Hai điểm trùng tọa độ: hiển thị 0 km, không gọi API.
- Khi có điểm đến, ẩn tuyến demo để không nhầm với tuyến Routing. Marker tài xế vẫn là mô phỏng, không phải GPS thật.

Thông số có thể chỉnh khi khởi tạo `RouteController(rerouteDistanceMeters: 50, minRequestInterval: Duration(seconds: 10), ...)`. Giai đoạn tiếp theo có thể theo dõi vị trí trên geometry để cắt phần đã đi và chỉ reroute khi lệch tuyến.

## Tên đường trên tuyến

`destination-polyline` nằm trên ảnh tile nên có thể che chữ đã in trong ảnh. Raster tiles không cung cấp tọa độ hay bounding box của chữ; hiện không có phát hiện chính xác từng nhãn bị che. App vẽ lại **tên đường của tuyến** lên trên polyline, không đọc chữ từ ảnh/OCR.

Routing request của cả đường ngắn và đường chính yêu cầu `details=route_details`. Parser lấy `legs[].steps[].name`, `from_index`, `to_index` để ánh xạ sang geometry của đúng leg. Bỏ tên rỗng hoặc chỉ số không hợp lệ; không đoán tên bị thiếu. `road_labels.dart` gộp các step liền kề cùng tên, đặt nhãn theo chiều dài geometry, mặc định mỗi 250m trên đoạn dài và tại giữa đoạn ngắn. Đây là vị trí nhãn mới, không phải vị trí chữ gốc của tile.

`RoadLabelsLayer` được đặt sau `destination-polyline` và trước các marker tài xế/điểm đến. Nhãn chữ tối trên nền trắng, giữ nằm ngang khi xoay bản đồ, không chặn thao tác chạm. Lớp này tự loại nhãn chồng nhau theo tọa độ màn hình, chỉ vẽ nhãn trong viewport, tối đa 60 nhãn và ẩn dưới zoom 14. Nó không kiểm tra va chạm với chữ có sẵn trong ảnh tile.

Các giá trị có thể chỉnh:

- `buildRoadLabels(..., spacingMeters: 250, maxLabels: 2000)` trong parser: khoảng cách neo nhãn và số neo tối đa mỗi tuyến.
- `RoadLabelsLayer(minZoom: 14, labelGap: 12, maxVisibleLabels: 60, ...)`: ngưỡng zoom, khoảng trống giữa nhãn và giới hạn nhãn hiển thị.

Tọa độ neo được tạo khi nhận tuyến; các sự kiện la bàn/animation tài xế không tính lại chúng. Chỉ cập nhật lựa chọn hiển thị theo camera khi pan/zoom/xoay. `route_details` có thể tăng chi phí API, kể cả tuyến đi bộ/đường ngắn nay yêu cầu tên đường. Nếu cần line nằm dưới **chính nhãn gốc**, cần chuyển sang vector map có lớp road và label riêng để sắp thứ tự route dưới lớp label.

## Backend

Khi triển khai, giữ API key trên server, app gọi endpoint của bạn với điểm xuất phát/đích; backend gọi Geoapify và trả geometry cùng khoảng cách. Dart define trong app không bảo mật key. Thay adapter qua `TrackingPage(routingService: ...)` mà không đổi UI.

## Kiểm tra

Tests dùng HTTP giả lập để kiểm tra request, thứ tự lat/lon, geometry nhiều phần, khoảng cách theo đường, dữ liệu lỗi và quota. Tests controller kiểm tra hạn chế tần suất, vị trí mới nhất, đổi đích và bỏ phản hồi cũ. Test UI kiểm tra polyline có điểm trung gian từ RoutingService và số km từ service thay vì khoảng cách đường chim bay. Chưa xác minh tuyến thực tế, độ đầy đủ của dữ liệu tại Việt Nam và quy tắc phương tiện trên máy thật.
