# Tìm kiếm địa chỉ

## Luồng UI hiện tại

Sau khi có GPS, bấm nút biểu tượng chỉ đường bên phải bản đồ để mở lớp tìm kiếm. Có thanh chọn Xe máy, Ô tô, Đi bộ và Xe bus để tính tuyến theo phương tiện; lựa chọn được giữ khi mở lại lớp tìm kiếm. Nhập ít nhất 3 ký tự; app chờ 400ms rồi gọi API. Kết quả mới thay thế kết quả cũ; phản hồi của truy vấn đã thay đổi/đã xóa/đã đóng được bỏ qua. Đây là bỏ phản hồi cũ, không hủy request HTTP đã gửi.

Chọn kết quả để đóng lớp tìm kiếm, hiển thị tên và marker điểm đến, di chuyển camera đến đó trong 2 giây. Bấm X trên thẻ điểm đến để xóa. Khi có GPS và điểm đến, app gọi Routing API lấy tuyến theo đường và hiển thị chiều dài tuyến theo km. Geometry tuyến được vẽ bằng PolylineLayer màu xanh. Xem [luồng Routing và cách chuyển tọa độ thành polyline](ROUTING.md). Tuyến xanh nhiều waypoint chỉ còn hiển thị khi chưa chọn điểm đến; marker tài xế vẫn chạy mô phỏng.


## Cấu hình API

Đang tích hợp [Geoapify Address Autocomplete](https://apidocs.geoapify.com/docs/geocoding/address-autocomplete/).

1. Đăng ký/đăng nhập [Geoapify MyProjects](https://myprojects.geoapify.com/).
2. Tạo project, vào API Keys, lấy key và thử Address Autocomplete trong playground.
3. Dừng app và chạy lại với key thử nghiệm (không commit key vào mã nguồn):

```sh
flutter run --dart-define=GEOAPIFY_API_KEY=YOUR_KEY
```

Trên máy hiện tại nếu Flutter chưa có trong PATH:

```sh
/Users/trantrang/fvm/versions/3.32.8/bin/flutter run --dart-define=GEOAPIFY_API_KEY=YOUR_KEY
```

Dart define là cấu hình build, hot reload không đổi key. Nếu chưa có key, UI báo chưa cấu hình thay vì trả về địa chỉ giả.

## Request đã triển khai

`GeoapifyAddressSearch.search()` trong `lib/address_search/address_search_service.dart` dùng `Uri.https` để encode input và GET:

```text
https://api.geoapify.com/v1/geocode/autocomplete
  ?text=<địa chỉ đang gõ>
  &format=json
  &lang=vi
  &filter=countrycode:vn
  &limit=5
  &bias=proximity:<longitude>,<latitude>
  &apiKey=<key>
```

`bias` ưu tiên gần GPS hiện tại, không giới hạn bán kính. `filter=countrycode:vn` chỉ lấy tại Việt Nam; đổi/bỏ tham số này nếu muốn tìm nước khác. Bias lấy một lần khi mở lớp tìm kiếm, không gọi lại theo từng điểm GPS.

Response JSON có dạng:

```json
{
  "results": [
    {
      "place_id": "provider-id",
      "formatted": "Địa chỉ hiển thị",
      "lat": 21.03,
      "lon": 105.85
    }
  ]
}
```

Đọc `formatted` cho danh sách và `LatLng(lat, lon)` cho bản đồ. API bias dùng **lon,lat**, còn `LatLng` dùng **lat,lon**. Adapter kiểm tra tọa độ và bỏ mục trùng/không hợp lệ. Request timeout sau 8 giây; có thông báo lỗi key, vượt quota và lỗi kết nối. Không log URL có key hoặc response chứa địa chỉ.

## Đưa qua backend khi triển khai thật

Bản demo gọi Geoapify trực tiếp. Key truyền bằng dart-define vẫn có thể trích xuất từ app; đây không phải kho bí mật. Với bản triển khai, giữ key trên backend và gọi qua endpoint của bạn:

```text
Flutter -> GET /api/addresses/autocomplete?q=...&lat=...&lon=...
Backend -> Geoapify (gắn key từ biến môi trường của server)
Backend -> { results: [{ id, label, latitude, longitude }] }
```

Backend xác thực người dùng, giới hạn tần suất/độ dài query, đặt timeout và trả lỗi gọn. Tạo adapter mới implement `AddressSearchService`, map JSON về `AddressSuggestion`, rồi truyền qua `TrackingPage(addressSearchService: ...)`. Adapter được truyền vào do bên tạo quản lý vòng đời; adapter mặc định được trang đóng khi dispose. Đọc [hướng dẫn API key](https://myprojects.geoapify.com/help/api-keys/) để cấu hình hạn chế phù hợp server. Nhập và vị trí bias được gửi đến dịch vụ tìm địa chỉ; chỉ gửi thông tin cần thiết.

## Vẽ tuyến sau khi chọn địa chỉ

Đã tích hợp Routing API, dùng cùng GEOAPIFY_API_KEY. Xem [hướng dẫn tìm tuyến bám theo mạng đường](ROUTING.md).

## Kiểm tra

Đã có test với HTTP giả lập: query encoding, thứ tự tọa độ, dữ liệu trùng/sai, thiếu key/quota, debounce và phản hồi cũ. Test UI mở tìm kiếm, chọn kết quả, cập nhật camera/marker, xóa điểm đến. Chưa gọi API thật vì chưa có key; chất lượng địa chỉ và mạng thực tế cần kiểm tra trên máy thật.
