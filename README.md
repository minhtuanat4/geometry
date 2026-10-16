# Realtime delivery tracking

Ứng dụng Flutter dùng GPS và la bàn thật của điện thoại để hiển thị tài xế, tìm điểm đến và cập nhật tuyến đường. Đã bỏ DemoTracking, tuyến giả lập, timer di chuyển và thông tin đơn hàng/tài xế mẫu.

## Chạy

SDK của dự án: Flutter 3.32.8 / Dart 3.8. Khi thêm plugin native cần dừng app rồi chạy lại hoàn toàn.

```sh
flutter pub get
flutter run --dart-define=GEOAPIFY_API_KEY=your-key
```

Nếu Flutter chưa có trong PATH:

```sh
/Users/trantrang/fvm/versions/3.32.8/bin/flutter run --dart-define=GEOAPIFY_API_KEY=your-key
```

Tiles OpenStreetMap không cần key. Tìm địa chỉ và routing Geoapify cần `GEOAPIFY_API_KEY`; xem [tìm địa chỉ](docs/ADDRESS_SEARCH.md) và [routing](docs/ROUTING.md). Không commit key thật. `ROUTING_MODE` mặc định `motorcycle`; có thể chọn phương tiện trong màn hình tìm điểm đến.

## Vị trí thật

- `geolocator` nhận GPS; `flutter_compass` nhận hướng điện thoại, không suy hướng từ GPS course khi đứng yên.
- Màn hình tự kiểm tra GPS và xin quyền khi sử dụng. Chưa có vị trí thì chờ GPS; không có tọa độ dự phòng hay chuyển động giả lập.
- Marker dùng GPS trực tiếp khi chưa có tuyến, GPS đã khớp tuyến khi đang chỉ đường. `ValueNotifier<LatLng?>` là nguồn hiển thị thống nhất cho marker và nút camera.
- `_DriverLayer` nội suy chuyển động 1 giây giữa các điểm thực, không phát sinh điểm GPS đầu vào. Không có điểm mới thì marker đứng yên. Mất GPS hoặc vào nền sẽ ẩn marker, hủy animation camera và chờ vị trí mới.
- Camera đi theo GPS; kéo/zoom tạm ngắt. Nút **Về vị trí của tôi** bật lại chế độ đi theo. Nút **Về vị trí tài xế** nội suy vị trí và zoom hiện tại về 15.3 trong 2 giây.
- Android khai báo INTERNET, fine/coarse location. iOS dùng When In Use và cờ CocoaPods bỏ yêu cầu Always. Chỉ thu thập khi ứng dụng ở foreground; chưa cấu hình GPS background.
- GPS high accuracy, distanceFilter 3m; Android đề nghị chu kỳ 1 giây. Tần suất thực tế do hệ điều hành/phần cứng quyết định.
- Cấu hình lọc góc, chu kỳ và animation tại `HeadingSettings` trong `lib/tracking/heading_filter.dart`. Góc được so với hướng được chấp nhận gần nhất, xử lý qua Bắc theo vòng quay ngắn nhất. Thiếu la bàn thì ẩn mũi tên và giữ marker GPS.

Hiện vị trí tài xế là **thiết bị đang chạy ứng dụng**, chưa có truyền vị trí tài xế từ máy khác qua backend. Tìm đường gửi vị trí hiện tại/điểm đến tới Geoapify; tiles được tải qua mạng.

## Polyline trong phiên chỉ đường

`RouteProgress` chiếu GPS lên từng đoạn còn lại của geometry, giữ đỉnh trung gian và không nối các phần MultiLineString qua khoảng trống. Con trỏ không lùi do rung nhẹ; polyline chỉ vẽ phần đường còn lại, bắt đầu tại điểm khớp mới. Đây chưa phải lịch sử GPS đã đi.

Cấu hình trong `RouteController`:

- `snapDistanceMeters: 35`: trong 35m thì khớp GPS vào tuyến.
- `rerouteDistanceMeters: 50`: từ 50m ngoài tuyến thì tìm lại đường từ GPS mới nhất đến điểm đến.
- `minRequestInterval: Duration(seconds: 10)`: giới hạn gọi lại API; dùng vị trí mới nhất khi hết thời gian chờ.

Từ 35m đến dưới 50m, marker hiển thị GPS thật và báo lệch tuyến nhưng chưa yêu cầu tuyến mới. Khi chờ/lỗi API, giữ tuyến cũ và cho phép thử lại. Tuyến mới dùng geometry của provider; không vẽ đường thẳng thay thế. Đi dọc tuyến không tự gọi lại routing API.

Đây là khớp hình học, chưa phải map matching theo mạng đường. Hai đường song song/giao cắt hoặc GPS kém có thể gây nhầm. Chưa lọc GPS nhảy theo tốc độ/độ chính xác trong RouteController; cần kiểm tra thực địa. La bàn cũng chịu nhiễu từ, tư thế cầm máy và khác biệt Bắc từ/Bắc địa lý.

## Phạm vi cập nhật và kiểm tra

Không dùng setState trong main.dart. GPS cập nhật notifier vị trí và trạng thái tuyến; marker animation chỉ cập nhật MarkerLayer, mũi tên chỉ lắng nghe heading. Icon được tái sử dụng qua AnimatedBuilder.child. Timer/listener/controller được giải phóng khi rời màn hình.

```sh
flutter analyze
flutter test
flutter run --profile --dart-define=GEOAPIFY_API_KEY=your-key
```

Test dùng nguồn cảm biến/API thay thế **chỉ trong test**, không tải tiles: kiểm tra marker không tự di chuyển, chờ/mất GPS, foreground/background, hướng la bàn, camera 2 giây, lựa chọn phương tiện, khớp tuyến, lệch tuyến và phản hồi API cũ.

Thử trên Android/iPhone thật: cấp/từ chối quyền, tắt/bật GPS, đi bộ vài mét, xoay qua Bắc, kéo/zoom, chuyển nền/quay lại, đi lệch tuyến và mất mạng. Chưa xác minh GPS, tiles, FPS hoặc pin trên thiết bị thật trong môi trường kiểm thử này. Dùng DevTools Performance trên máy thật để đo UI/raster frame time và frame giật; camera pan/zoom vẫn có thể cập nhật các lớp bản đồ.

Tiles mặc định: `https://tile.openstreetmap.org/{z}/{x}/{y}.png`, có attribution, User-Agent theo application ID và caching của flutter_map. Không tải offline/bulk. Có thể đổi bằng `TILE_URL`; provider mới có thể cần key/attribution riêng. Public tiles tuân theo [chính sách OSM](https://operations.osmfoundation.org/policies/tiles/), không có SLA.
