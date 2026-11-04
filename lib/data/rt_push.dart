// Push source for the realtime feed.
//
// Treska's relay (relay/, FeedHub) keeps one WebSocket per app and sends
// ZET's protobuf, gzipped and otherwise unchanged, as soon as ZET publishes a
// new one (~1 s after ZET, instead of waiting for the next 5 s poll). The
// worker keeps polling whenever this socket is down or quiet, so the relay is
// a speed-up, never a dependency.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class RtPush {
  static const String _userAgent = 'Treska/2.0 (Flutter; ZET timetable)';

  final String url;
  final void Function(Uint8List protobuf) onFeed;
  final Duration connectTimeout;

  /// ZET publishes every ~10-12 s; a socket quiet for this long is treated as
  /// half-open and replaced.
  final Duration silenceTimeout;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  Timer? _silence;
  int _attempt = 0;
  bool _closed = false;

  RtPush({
    required this.url,
    required this.onFeed,
    this.connectTimeout = const Duration(seconds: 8),
    this.silenceTimeout = const Duration(seconds: 45),
  });

  bool get connected => _socket != null;

  void start() => unawaited(_connect());

  Future<void> _connect() async {
    if (_closed) return;
    _retry = null;
    try {
      final client = HttpClient()
        ..userAgent = _userAgent
        ..connectionTimeout = connectTimeout;
      final socket = await WebSocket.connect(url, customClient: client)
          .timeout(connectTimeout);
      if (_closed) {
        await socket.close();
        return;
      }
      // Protocol pings are free on Cloudflare and catch dead mobile links.
      socket.pingInterval = const Duration(seconds: 20);
      _socket = socket;
      _attempt = 0;
      _armSilence();
      _sub = socket.listen(
        _onMessage,
        onDone: _onDown,
        onError: (Object _) => _onDown(),
        cancelOnError: true,
      );
    } catch (_) {
      _onDown();
    }
  }

  void _onMessage(dynamic message) {
    if (message is! List<int>) return;
    try {
      final bytes = gzip.decode(message);
      if (bytes.length < 100) return;
      _armSilence();
      onFeed(Uint8List.fromList(bytes));
    } catch (_) {
      // A corrupt frame is skipped; the next one or the poll replaces it.
    }
  }

  void _armSilence() {
    _silence?.cancel();
    _silence = Timer(silenceTimeout, _onDown);
  }

  void _onDown() {
    _silence?.cancel();
    _silence = null;
    _sub?.cancel();
    _sub = null;
    final socket = _socket;
    _socket = null;
    if (socket != null) unawaited(socket.close().catchError((_) {}));
    if (_closed || _retry != null) return;
    // 2, 4, 8 … 60 s between attempts.
    final delay = Duration(seconds: (2 << _attempt.clamp(0, 5)).clamp(2, 60));
    _attempt++;
    _retry = Timer(delay, () => unawaited(_connect()));
  }

  void close() {
    _closed = true;
    _retry?.cancel();
    _retry = null;
    _onDown();
  }
}
