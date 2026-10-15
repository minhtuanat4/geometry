import 'package:flutter/material.dart';

import 'device_location.dart';

class DeviceLocationControls extends StatelessWidget {
  const DeviceLocationControls({
    super.key,
    required this.device,
    required this.onCenter,
  });
  final DeviceLocation device;
  final VoidCallback onCenter;

  @override
  Widget build(BuildContext context) => Positioned(
    left: 12,
    bottom: 30,
    child: SizedBox(
      width: 235,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: ListenableBuilder(
            listenable: device,
            builder: (context, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(device.status, style: const TextStyle(fontSize: 12)),
                if (device.enabled)
                  Text(
                    device.compassStatus,
                    style: const TextStyle(fontSize: 11),
                  ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton(
                      onPressed: device.busy
                          ? null
                          : () {
                              if (device.action == LocationAction.retry) {
                                device.start();
                              } else {
                                device.openSettings();
                              }
                            },
                      child: Text(
                        device.action != LocationAction.retry
                            ? 'Mở cài đặt'
                            : device.enabled
                            ? 'Thử lại GPS'
                            : 'Bật vị trí',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Về vị trí của tôi',
                      onPressed: device.position.value == null
                          ? null
                          : () {
                              onCenter();
                            },
                      icon: const Icon(Icons.person_pin_circle_outlined),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
