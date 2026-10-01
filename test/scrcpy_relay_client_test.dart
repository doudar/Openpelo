import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openpelo/services/scrcpy_protocol.dart';
import 'package:openpelo/services/scrcpy_relay_client.dart';

void main() {
  test(
    'idle relay sends valid null TS packets and accepts later video',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final http = HttpClient();
      final connected = Completer<ScrcpyRelayClient>();
      final listener = server.listen((request) {
        request.response.bufferOutput = false;
        connected.complete(ScrcpyRelayClient(request.response));
      });
      ScrcpyRelayClient? relay;
      StreamSubscription<List<int>>? subscription;
      try {
        final request = await http.getUrl(
          Uri.parse('http://127.0.0.1:${server.port}'),
        );
        final responseFuture = request.close();
        relay = await connected.future;
        final response = await responseFuture.timeout(
          const Duration(seconds: 3),
        );
        final received = <int>[];
        final idle = Completer<void>();
        final video = Completer<void>();
        final done = Completer<void>();
        subscription = response.listen((chunk) {
          received.addAll(chunk);
          if (received.length >= 188 * 192 && !idle.isCompleted) {
            idle.complete();
          }
          for (var i = 0; i + 188 <= received.length; i += 188) {
            final pid = ((received[i + 1] & 0x1f) << 8) | received[i + 2];
            if (pid == 0x100 && !video.isCompleted) video.complete();
          }
        }, onDone: done.complete);
        await idle.future.timeout(const Duration(seconds: 3));
        for (var i = 0; i < 188 * 192; i += 188) {
          expect(received.sublist(i, i + 4), [0x47, 0x1f, 0xff, 0x10]);
          expect(received.sublist(i + 4, i + 188), everyElement(0xff));
        }
        expect(
          relay.addPacket(
            ScrcpyVideoPacket(
              bytes: Uint8List.fromList([0, 0, 0, 1, 0x65, 0x80]),
              timestampUs: 1000000,
              isConfig: false,
              isKeyFrame: true,
            ),
          ),
          isTrue,
        );
        await video.future.timeout(const Duration(seconds: 3));
        relay.close();
        await done.future.timeout(const Duration(seconds: 3));
        expect(relay.addConfig(Uint8List(1)), isFalse);
      } finally {
        relay?.close();
        await subscription?.cancel();
        http.close(force: true);
        await listener.cancel();
        await server.close(force: true);
      }
    },
  );
}
