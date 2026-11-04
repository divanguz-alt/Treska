import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:zet2/data/rt_push.dart';

/// A stand-in for the relay's FeedHub: sends gzipped frames to each client.
Future<HttpServer> _hub(void Function(WebSocket socket) onClient) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    onClient(await WebSocketTransformer.upgrade(request));
  });
  return server;
}

Uint8List _feed(int marker) => Uint8List(500)..[0] = marker;

void main() {
  test('pushed frames arrive ungzipped, and the client reconnects', () async {
    final sockets = <WebSocket>[];
    final server = await _hub((socket) {
      sockets.add(socket);
      socket.add(gzip.encode(_feed(sockets.length)));
    });
    final received = <int>[];
    final second = Completer<void>();
    final push = RtPush(
      url: 'ws://127.0.0.1:${server.port}/ws',
      onFeed: (bytes) {
        received.add(bytes[0]);
        if (received.length == 2) second.complete();
      },
    )..start();

    // First connection delivers feed 1; dropping it must lead to a reconnect
    // that delivers feed 2.
    while (received.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(push.connected, isTrue);
    await sockets.first.close();
    await second.future.timeout(const Duration(seconds: 10));
    expect(received, [1, 2]);

    push.close();
    expect(push.connected, isFalse);
    await server.close(force: true);
  });

  test('frames that are not gzipped feeds are ignored', () async {
    final server = await _hub((socket) {
      socket.add('text frame');
      socket.add([1, 2, 3]);
      socket.add(gzip.encode(Uint8List(10)));
      socket.add(gzip.encode(_feed(7)));
    });
    final received = <int>[];
    final push = RtPush(
      url: 'ws://127.0.0.1:${server.port}/ws',
      onFeed: (bytes) => received.add(bytes[0]),
    )..start();
    while (received.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(received, [7]);
    push.close();
    await server.close(force: true);
  });
}
