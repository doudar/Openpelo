import 'scrcpy_protocol.dart';

/// Retains a bounded, decodable group of pictures for a late preview client.
/// A still display may not produce another keyframe until it changes.
class ScrcpyPreviewBuffer {
  final int maxBytes;
  final List<ScrcpyVideoPacket> _packets = [];
  int _bytes = 0;

  ScrcpyPreviewBuffer({this.maxBytes = 4 * 1024 * 1024});

  Iterable<ScrcpyVideoPacket> get packets => _packets;

  void add(ScrcpyVideoPacket packet) {
    if (packet.isConfig || packet.isKeyFrame) {
      _packets.clear();
      _bytes = 0;
    }
    if (packet.isConfig) return;
    if (_packets.isEmpty && !packet.isKeyFrame) return;
    if (_bytes + packet.bytes.length > maxBytes) {
      // Dropping any reference frame invalidates the rest of this GOP.
      _packets.clear();
      _bytes = 0;
      return;
    }
    _packets.add(packet);
    _bytes += packet.bytes.length;
  }
}
