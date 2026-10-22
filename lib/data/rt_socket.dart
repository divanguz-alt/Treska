// Streaming realtime source.
//
// ZET publishes a fresh feed roughly every 10 seconds — much faster than the
// ~2 minute age of the vehicle fixes inside it. Polling `gtfs-rt-protobuf`
// over HTTPS only samples that stream every N seconds and pays a full
// TLS + HTTP round trip each time. zet.skoljka.org relays the same snapshots
// over a WebSocket, so a client sees each new feed the moment it is produced.
//
// The relay speaks JSON and currently sends *decoded* vehicle state (see
// [parseWireFeed]) plus occasional news/app-version notices that share the
// socket. Older builds of the relay shipped `{"kind":"realtime",
// "gzipped_data":"<hex>"}` with the raw protobuf; both are accepted.
//
// This class keeps trying to stay connected; [onFeed] runs for every snapshot.
// The worker falls back to REST polling whenever the socket is down, so a relay
// outage degrades freshness but never breaks the app.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'gtfs_rt.dart';
import 'wire_feed.dart';

class RtSocket {
  static const String defaultUrl = 'wss://zet.skoljka.org/ws-v4?appUpdates=1';
  static const String _userAgent = 'Treska/2.0 (Flutter; ZET timetable)';

  final String url;
  final void Function(RtFeed feed, DateTime receivedAt) onFeed;
  final void Function(String error)? onError;
  final Duration connectTimeout;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  Timer? _silence;
  DateTime? _lastSnapshotAt;
  int _attempt = 0;
  bool _started = false;
  bool _closed = false;

  RtSocket({
    required this.onFeed,
    this.onError,
    this.url = defaultUrl,
    this.connectTimeout = const Duration(seconds: 8),
  });

  bool get connected => _socket != null;

  /// True once a snapshot arrived recently enough to prefer over REST.
  bool get fresh =>
      _lastSnapshotAt != null &&
      DateTime.now().difference(_lastSnapshotAt!) <
          const Duration(seconds: 45);

  void start() {
    if (_started) return;
    _started = true;
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (_closed) return;
    _retry?.cancel();
    _retry = null;

    try {
      final socket = await WebSocket.connect(
        url,
        customClient: _client(),
      ).timeout(connectTimeout);
      if (_closed) {
        socket.close();
        return;
      }
      socket.pingInterval = const Duration(seconds: 20);
      _socket = socket;
      _attempt = 0;
      _armSilenceWatchdog();

      _sub = socket.listen(
        _onMessage,
        onDone: _onDown,
        onError: (Object e) {
          _report('WS: $e');
          _onDown();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _report('WS: $e');
      _onDown();
    }
  }

  HttpClient _client() {
    final client = HttpClient();
    client.userAgent = _userAgent;
    client.connectionTimeout = connectTimeout;
    client.idleTimeout = const Duration(seconds: 60);
    return client;
  }

  void _onMessage(dynamic message) {
    if (message is! String) return;
    // News / app-version notices share this socket and carry no vehicles.
    if (!message.contains('"vehicles"') && !message.contains('gzipped_data')) {
      return;
    }

    final receivedAt = DateTime.now();
    try {
      final feed = message.contains('gzipped_data')
          ? _fromGzipped(message)
          : parseWireFeed(message);
      if (feed == null) return;

      _lastSnapshotAt = receivedAt;
      _armSilenceWatchdog();
      onFeed(feed, receivedAt);
    } catch (e) {
      _report('WS decode: $e');
    }
  }

  /// Older relay format: the raw protobuf, gzipped and hex encoded.
  RtFeed? _fromGzipped(String message) {
    final decoded = jsonDecode(message);
    if (decoded is! Map) return null;
    final hex = decoded['gzipped_data'];
    if (hex is! String || hex.isEmpty) return null;
    final bytes = gzip.decode(_fromHex(hex));
    if (bytes.length < 100) return null;
    return parseRtFeed(Uint8List.fromList(bytes));
  }

  /// A half-open socket can linger without ever erroring. If no snapshot shows
  /// up for a while, drop it so REST polling takes over.
  void _armSilenceWatchdog() {
    _silence?.cancel();
    _silence = Timer(const Duration(seconds: 90), _onDown);
  }

  void _onDown() {
    _silence?.cancel();
    _silence = null;
    _sub?.cancel();
    _sub = null;
    final socket = _socket;
    _socket = null;
    try {
      socket?.close();
    } catch (_) {}

    if (_closed || _retry != null) return;
    // 1s, 2s, 3s … capped at 5s: fast enough to recover within one feed tick.
    final delay = Duration(seconds: (_attempt + 1).clamp(1, 5));
    _attempt++;
    _retry = Timer(delay, () {
      _retry = null;
      unawaited(_connect());
    });
  }

  void _report(String error) => onError?.call(error);

  Future<void> dispose() async {
    _closed = true;
    _silence?.cancel();
    _retry?.cancel();
    await _sub?.cancel();
    _sub = null;
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
  }

  // ── hex ───────────────────────────────────────────────────────────────────

  static final List<int> _nibbles = _buildNibbles();

  static List<int> _buildNibbles() {
    final table = List<int>.filled(256, -1);
    for (var i = 0; i < 10; i++) {
      table[0x30 + i] = i;
    }
    for (var i = 0; i < 6; i++) {
      table[0x61 + i] = 10 + i;
      table[0x41 + i] = 10 + i;
    }
    return table;
  }

  Uint8List _fromHex(String hex) {
    final n = hex.length ~/ 2;
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      final hi = _nibbles[hex.codeUnitAt(i * 2)];
      final lo = _nibbles[hex.codeUnitAt(i * 2 + 1)];
      if (hi < 0 || lo < 0) {
        throw const FormatException('bad hex');
      }
      out[i] = (hi << 4) | lo;
    }
    return out;
  }
}
