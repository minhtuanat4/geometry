# Realtime food delivery map demo

Bản thử nghiệm Flutter: theo dõi một tài xế trên bản đồ quanh vị trí thiết bị, có thêm vị trí GPS và hướng điện thoại thật; chưa dùng backend.

## Chạy

SDK hiện có của dự án: Flutter 3.32.8 / Dart 3.8.

```sh
flutter pub get
flutter run
```

Nếu Flutter chưa có trong PATH trên máy hiện tại:

```sh
/Users/trantrang/fvm/versions/3.32.8/bin/flutter run
```

Bản đồ cần internet, không cần API key. Android đã khai báo INTERNET; tính năng vị trí thiết bị xin quyền khi bạn bấm “Bật vị trí”.

## Cấu hình đang dùng

- `flutter_map` 8.3.2 + `latlong2`.
- Tile OpenStreetMap, attribution hiển thị trên bản đồ, User-Agent theo application ID.
- Giữ caching mặc định của flutter_map 8.3.2; không tải bản đồ offline/bulk.
- 1 vị trí giả lập/giây, hoàn thành sau 120 giây chạy. Thời gian này là thời gian mô phỏng, không phải ETA thực tế.
- Waypoint minh họa, không phải kết quả tìm đường; không đảm bảo bám làn/đường thực tế.
- Có tạm dừng/tiếp tục, chạy lại, đưa camera về tài xế. Camera không tự chạy theo từng frame.

Có thể đổi tile provider (provider mới có thể cần key và attribution riêng):

```sh
flutter run --dart-define='TILE_URL=https://your-provider/{z}/{x}/{y}.png'
```

OpenStreetMap public tiles dành cho thử nghiệm tương tác phù hợp [chính sách sử dụng](https://operations.osmfoundation.org/policies/tiles/), không có SLA. Khi triển khai thật, chọn dịch vụ tiles có hạn mức, giá và SLA phù hợp.

## Cách tách cập nhật

`DemoTracking` (`lib/tracking/demo_tracking.dart`) giữ timer, tiến độ và vị trí; mỗi giây phát một thông báo. `_DriverLayer` trong `lib/main.dart` nội suy từ vị trí đang vẽ đến điểm nhận mới bằng AnimationController. Animation chỉ rebuild MarkerLayer của tài xế; tile, tuyến và thông tin đơn hàng không được rebuild bởi callback animation. Nội suy kéo dài 1 giây nên có độ trễ hiển thị tối đa khoảng một chu kỳ so với điểm vừa nhận.

Widget icon tài xế được tái sử dụng qua `AnimatedBuilder.child`. RepaintBoundary tách vùng bản đồ khỏi vùng thông tin. Bộ đếm cập nhật 1 Hz; không gọi API tìm đường trong vòng lặp. Mô phỏng tạm dừng khi app không ở foreground, tiếp tục khi quay lại nếu trước đó đang chạy. Timer/listener/controller được giải phóng khi rời màn hình.

Đây là nền tảng tối ưu phạm vi cập nhật, chưa phải kết luận đã đạt hiệu năng tối đa.

## Kiểm tra và đo

```sh
flutter analyze
flutter test
flutter run --profile
```

Đo trên điện thoại thật trong Flutter DevTools Performance:

1. Chờ tiles tải xong; ghi một lượt 120 giây, gồm di chuyển marker và thao tác pan/zoom.
2. Xem UI/raster frame time và số frame giật; mục tiêu ban đầu cho máy 60 Hz là dưới khoảng 16.7 ms/frame. Màn hình 120 Hz có ngân sách khoảng 8.3 ms/frame.
3. Bật theo dõi widget builds để kiểm tra animation không rebuild toàn bộ trang. Việc pan/zoom vẫn có thể khiến các lớp bản đồ cập nhật theo camera.
4. Kiểm tra Memory qua nhiều lượt chạy lại; kiểm tra Network để tách request tiles khỏi dữ liệu vị trí. Demo không có lưu lượng vị trí qua mạng.
5. Đo thêm trên máy Android cấu hình thấp và iPhone, ghi model/OS, UI/raster p95, frame giật và bộ nhớ trước khi so sánh giải pháp.

Tests chạy không tải tiles: kiểm tra chu kỳ mô phỏng, điều khiển, điểm kết thúc và pause/resume theo lifecycle. Chưa xác minh tiles qua mạng và FPS/pin trên thiết bị thật.

## Bước tiếp theo khi nối realtime thật

Đề xuất bắt đầu với Firebase Realtime Database cho MVP: một bản ghi vị trí mới nhất theo chuyến giao, khách chỉ subscribe chuyến được cấp quyền. Đây là lựa chọn triển khai tiếp theo, chưa được tích hợp.

Payload dự kiến: `deliveryId`, `sequence`, `latitude`, `longitude`, `recordedAt`, `accuracy`, `heading`. Tách nguồn nhận stream khỏi phần vẽ; từ chối gói sai thứ tự, hết hạn hoặc không hợp lệ; hiển thị trạng thái mất kết nối/dữ liệu cũ và xử lý reconnect. Tần suất 1–2 giây lúc di chuyển chỉ là điểm bắt đầu để đo; điều chỉnh theo độ trễ, pin và chi phí. GPS background của app tài xế cần thiết kế riêng; cơ chế dừng ở nền trong demo này dành cho màn hình khách theo dõi.

## Vị trí và hướng điện thoại realtime

- `geolocator` nhận vị trí thiết bị; `flutter_compass` nhận hướng điện thoại (không dùng GPS course để suy ra hướng khi đứng yên).
- Khi mở màn hình, ứng dụng tự xin quyền khi sử dụng và chờ GPS trước khi khởi tạo bản đồ. Khi lỗi, dùng nút thử lại/mở cài đặt. Bấm nút hình người trong thẻ GPS để đưa bản đồ đến vị trí của bạn; nút bên phải vẫn đưa về tài xế giả lập.
- Android xin cả fine/coarse location, vẫn chấp nhận quyền vị trí gần đúng. iOS dùng When In Use và cờ CocoaPods bỏ yêu cầu Always.
- GPS high accuracy, distanceFilter 3m; Android đề nghị chu kỳ 1 giây. Tần suất và độ chính xác thực tế do hệ điều hành/phần cứng quyết định. Khi đứng yên GPS có thể không phát điểm mới.
- La bàn chỉ chấp nhận góc lệch lớn hơn 10° so với hướng đã nhận gần nhất, cách nhau tối thiểu 600ms; animation 500ms với easeInOutCubic theo vòng quay ngắn nhất. Cấu hình qua HeadingSettings trong lib/tracking/heading_filter.dart hoặc truyền vào DeviceLocation(headingSettings: ...). Đây là giới hạn cập nhật UI; cảm biến gốc vẫn có thể phát nhanh hơn.
- Marker giữ `rotate: false` để xoay cùng mặt bản đồ; mũi tên xoay tương đối với hướng Bắc của bản đồ. Camera đi theo vị trí GPS mới; thao tác kéo/zoom tạm ngắt đi theo, nút về vị trí của tôi bật lại. Không tự xoay camera. La bàn chỉ cập nhật mũi tên trong marker tài xế; chuyển động vị trí tái sử dụng subtree của marker qua `AnimatedBuilder.child`.
- Chỉ hiển thị khi app ở foreground; hủy stream khi vào nền/rời màn hình, kiểm tra lại quyền khi quay lại. Không cấu hình theo dõi GPS background.
- Có trạng thái GPS tắt, quyền bị từ chối/khóa và nút mở cài đặt/thử lại. Hướng la bàn hiển thị bằng mũi tên quanh marker tài xế trong `_DriverLayer`; không còn lớp marker thiết bị riêng. Khi không có la bàn, ẩn mũi tên và giữ biểu tượng tài xế. Tọa độ tài xế vẫn theo tuyến giả lập; camera vẫn theo GPS thiết bị.
- Ưu tiên thử trên điện thoại Android/iPhone thật. Simulator có thể không có la bàn. Heading phụ thuộc cảm biến/hệ điều hành (có thể là Bắc từ), nhiễu từ và tư thế cầm máy; không đảm bảo trùng tuyệt đối Bắc địa lý. Hiện không có hiệu chỉnh độ lệch từ riêng.

Sau khi thêm package native, cần **dừng app và chạy lại hoàn toàn**:

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

Kiểm tra thực tế: từ chối quyền rồi cấp lại trong Settings; tắt/bật GPS; xoay máy qua Bắc (359°/0°); xoay bản đồ bằng hai ngón và kiểm tra mũi tên vẫn cùng hướng địa lý; chuyển nền/quay lại; đi bộ vài mét và kiểm tra vị trí/sai số. Không dùng hot reload để đăng ký plugin mới.

Tuyến demo được tạo một lần quanh điểm GPS đầu tiên (các waypoint trong phạm vi khoảng 800m), không còn tọa độ TP.HCM cố định. Những điểm GPS tiếp theo chỉ cập nhật thiết bị và camera, không đặt lại tuyến/tiến độ mô phỏng. Chạy lại phát lại cùng tuyến trong phiên. Khi chưa có GPS hoặc bị từ chối quyền, bản đồ chưa được tạo và demo chưa chạy; trạng thái chờ và nút xử lý quyền vẫn hiển thị.

## Chọn điểm đến

Đã thêm nút **Chỉ đường** mở lớp tìm địa chỉ, gợi ý qua Geoapify Autocomplete và đánh dấu điểm đến. Cần cấu hình `GEOAPIFY_API_KEY`. Xem [hướng dẫn API và tích hợp backend](docs/ADDRESS_SEARCH.md). Đã tích hợp [Routing API để vẽ tuyến theo đường](docs/ROUTING.md), dùng cùng API key.
# geometry
