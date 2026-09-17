import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

/// A recording stopped before accepting an incompatible or invalid packet.
class ScrcpyRecordingException implements Exception {
  const ScrcpyRecordingException(this.message, {this.savedPath});
  final String message;
  final String? savedPath;
  @override
  String toString() => message;
}

/// Video-only H.264/AVC MP4 writer. Requires decode-order, no-B-frame packets.
///
/// Keeps only sample indexes in memory (at most [maxSamples]); compressed video
/// goes directly to a .partial file. Call [finish] on stop AND disconnect. The
/// destination is reserved exclusively, so an existing recording is never
/// overwritten. A crash can leave the reserved empty file and the partial file;
/// a partial file is not a finalized MP4. Finalization appends the sample tables.
class ScrcpyRecorder {
  ScrcpyRecorder._(
    this.path,
    this._width,
    this._height,
    this._partial,
    this._file,
  );

  static const int maxSamples = 1000000;
  static const int _timescale = 1000000;
  static const int _maxPendingBytes = 32 * 1024 * 1024;
  final String path;
  int _width;
  int _height;
  // The SPS is authoritative. Viewer decoder notifications can lag rotation.
  int get width => _width;
  int get height => _height;
  final File _partial;
  final RandomAccessFile _file;
  final List<int> _sizes = [];
  final List<int> _durations = [];
  final List<int> _syncSamples = [];
  Uint8List? _sps;
  Uint8List? _pps;
  Future<void> _queue = Future<void>.value();
  Future<String>? _finishFuture;
  int _pendingBytes = 0;
  int _lastTimestamp = 0;
  int _firstTimestamp = 0;
  int _mediaBytes = 0;
  bool _closed = false;
  bool _stopping = false;
  String? _savedPath;
  Object? _failure;

  int get sampleCount => _sizes.length;
  bool get isFinished => _closed;
  Duration get recordedDuration => Duration(
    microseconds: _sizes.isEmpty ? 0 : _lastTimestamp - _firstTimestamp,
  );

  static Future<ScrcpyRecorder> start({
    required String path,
    required int width,
    required int height,
    Uint8List? codecConfig,
  }) async {
    if (width < 1 || width > 65535 || height < 1 || height > 65535) {
      throw ArgumentError('Invalid video dimensions: $width x $height');
    }
    final destination = File(path);
    // The exclusive create is intentionally before any destructive open/rename.
    await destination.create(exclusive: true);
    final partial = File('$path.partial');
    RandomAccessFile? file;
    bool createdPartial = false;
    try {
      await partial.create(exclusive: true);
      createdPartial = true;
      file = await partial.open(mode: FileMode.write);
      await file.writeFrom(_ftyp());
      await file.writeFrom(_join([_u32(1), 'mdat'.codeUnits, _u64(16)]));
      final recorder = ScrcpyRecorder._(path, width, height, partial, file);
      if (codecConfig != null) recorder._acceptConfig(_nals(codecConfig));
      return recorder;
    } catch (_) {
      await file?.close();
      if (createdPartial) await partial.delete();
      await destination.delete();
      rethrow;
    }
  }

  /// Calls are serialized, including [finish]. The packet is copied so callers
  /// may reuse their network buffer. Await this future to apply backpressure.
  Future<void> addPacket(
    Uint8List bytes, {
    required int timestampUs,
    required bool isConfig,
    required bool isKeyFrame,
  }) {
    if (_stopping || _closed) {
      return Future.error(StateError('Recording has stopped.'));
    }
    if (_pendingBytes + bytes.length > _maxPendingBytes) {
      _stopping = true;
      final operation = _queue.then(
        (_) => _stopWithError(
          'Recording stopped because storage could not keep up with video.',
        ),
      );
      _queue = operation.then<void>((_) {}, onError: (Object _) {});
      return operation;
    }
    final copy = Uint8List.fromList(bytes);
    _pendingBytes += copy.length;
    final operation = _queue
        .then((_) async {
          if (_closed) throw StateError('Recording has stopped.');
          try {
            await _writePacket(copy, timestampUs, isConfig, isKeyFrame);
          } on ScrcpyRecordingException {
            rethrow;
          } catch (error) {
            await _stopWithError('Recording stopped: $error');
          }
        })
        .whenComplete(() => _pendingBytes -= copy.length);
    // Errors reach the individual caller; they must not poison the drain queue.
    _queue = operation.then<void>((_) {}, onError: (Object _) {});
    return operation;
  }

  Future<void> _writePacket(
    Uint8List bytes,
    int timestamp,
    bool config,
    bool key,
  ) async {
    final units = _nals(bytes);
    _acceptConfig(units);
    if (config) return;
    final media = units.where((nal) {
      final type = nal[0] & 31;
      return type != 7 && type != 8 && type != 9;
    }).toList();
    final vcl = media.where((nal) => (nal[0] & 31) >= 1 && (nal[0] & 31) <= 5);
    if (vcl.isEmpty) return;
    final idr = vcl.any((nal) => (nal[0] & 31) == 5);
    if (_sizes.isEmpty && (!idr || _sps == null || _pps == null)) return;
    if (vcl.any(_isBSlice)) {
      await _stopWithError(
        'Recording stopped: the encoder produced unsupported B-frames.',
      );
    }
    if (timestamp < 0 || (_sizes.isNotEmpty && timestamp <= _lastTimestamp)) {
      await _stopWithError(
        'Recording stopped: video timestamps are not increasing.',
      );
    }
    if (_sizes.length >= maxSamples) {
      await _stopWithError(
        'Recording reached its frame limit. Start another recording.',
      );
    }
    if (_sizes.isNotEmpty && timestamp - _lastTimestamp > 0xffffffff) {
      await _stopWithError(
        'Recording stopped after an unsupported gap in video.',
      );
    }
    final sample = _join([
      for (final nal in media) ...[_u32(nal.length), nal],
    ]);
    // Index only complete writes. On a disk error finalization truncates any
    // incomplete sample before writing moov, if storage still allows it.
    await _file.writeFrom(sample);
    if (_sizes.isEmpty) _firstTimestamp = timestamp;
    if (_sizes.isNotEmpty) _durations.add(timestamp - _lastTimestamp);
    _lastTimestamp = timestamp;
    _sizes.add(sample.length);
    _mediaBytes += sample.length;
    if (idr) _syncSamples.add(_sizes.length);
  }

  void _acceptConfig(List<Uint8List> units) {
    for (final nal in units) {
      final type = nal[0] & 31;
      if (type != 7 && type != 8) continue;
      if (nal.length > 65535 || (type == 7 && nal.length < 4)) {
        throw const FormatException('Invalid H.264 codec configuration.');
      }
      final old = type == 7 ? _sps : _pps;
      if (old != null && !_equal(old, nal)) {
        // Keep one immutable sample description for the entire clip.
        throw const FormatException(
          'Video configuration or orientation changed. Start a new recording.',
        );
      }
      if (type == 7) {
        final dimensions = _spsDimensions(nal);
        _width = dimensions.$1;
        _height = dimensions.$2;
        _sps = Uint8List.fromList(nal);
      }
      if (type == 8) _pps = Uint8List.fromList(nal);
    }
  }

  Future<Never> _stopWithError(String message) async {
    _stopping = true;
    try {
      await _finalize();
    } catch (error) {
      _failure = error;
    }
    final exception = ScrcpyRecordingException(message, savedPath: _savedPath);
    _failure ??= exception;
    throw exception;
  }

  Future<String> finish() {
    _stopping = true;
    return _finishFuture ??= _queue.then((_) async {
      if (!_closed) await _finalize();
      if (_savedPath != null) return _savedPath!;
      throw _failure ??
          const ScrcpyRecordingException('No video frames were recorded.');
    });
  }

  Future<void> _finalize() async {
    if (_closed) return;
    _closed = true;
    try {
      if (_sizes.isEmpty) {
        await _file.close();
        await _partial.delete();
        await File(path).delete();
        throw const ScrcpyRecordingException('No video keyframe was received.');
      }
      final durations = [
        ..._durations,
        _durations.isEmpty ? 33333 : _durations.last,
      ];
      final mediaStart = _ftyp().length + 16;
      await _file.truncate(mediaStart + _mediaBytes);
      await _file.setPosition(_ftyp().length + 8);
      await _file.writeFrom(_u64(_mediaBytes + 16));
      await _file.setPosition(mediaStart + _mediaBytes);
      await _file.writeFrom(
        _moov(
          width,
          height,
          _sps!,
          _pps!,
          _sizes,
          durations,
          _syncSamples,
          mediaStart,
        ),
      );
      await _file.flush();
      await _file.close();
      // Replaces only the empty file this writer exclusively reserved at start.
      await _partial.rename(path);
      _savedPath = path;
    } catch (error) {
      _failure = error;
      try {
        await _file.close();
      } catch (_) {
        /* Already closed. */
      }
      rethrow;
    }
  }

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Reads the SPS syntax through frame cropping (ITU-T H.264 7.3.2.1.1).
  /// All variable-length values and loops are bounded before allocation/use.
  static (int, int) _spsDimensions(Uint8List nal) {
    final bits = _H264Bits(nal);
    final profile = bits.read(8);
    bits.read(8); // constraint flags
    bits.read(8); // level_idc
    bits.ue(max: 31); // seq_parameter_set_id
    var chroma = 1;
    var separateColourPlane = false;
    if (const {
      100,
      110,
      122,
      244,
      44,
      83,
      86,
      118,
      128,
      138,
      139,
      134,
      135,
    }.contains(profile)) {
      chroma = bits.ue(max: 3);
      if (chroma == 3) separateColourPlane = bits.read(1) != 0;
      bits.ue(max: 6); // bit_depth_luma_minus8
      bits.ue(max: 6); // bit_depth_chroma_minus8
      bits.read(1); // qpprime_y_zero_transform_bypass_flag
      if (bits.read(1) != 0) {
        for (var i = 0; i < (chroma == 3 ? 12 : 8); i++) {
          if (bits.read(1) == 0) continue;
          var lastScale = 8;
          var nextScale = 8;
          for (var j = 0; j < (i < 6 ? 16 : 64); j++) {
            if (nextScale != 0) {
              nextScale = (lastScale + bits.se() + 256) % 256;
            }
            lastScale = nextScale == 0 ? lastScale : nextScale;
          }
        }
      }
    } else if (!const {66, 77, 88}.contains(profile)) {
      throw const FormatException('Unsupported H.264 SPS profile.');
    }
    bits.ue(max: 12); // log2_max_frame_num_minus4
    final poc = bits.ue(max: 2);
    if (poc == 0) {
      bits.ue(max: 12); // log2_max_pic_order_cnt_lsb_minus4
    } else if (poc == 1) {
      bits.read(1);
      bits.se();
      bits.se();
      final cycle = bits.ue(max: 255);
      for (var i = 0; i < cycle; i++) {
        bits.se();
      }
    }
    bits.ue(max: 16); // max_num_ref_frames
    bits.read(1); // gaps_in_frame_num_value_allowed_flag
    final columns = bits.ue(max: 4095) + 1;
    final rows = bits.ue(max: 4095) + 1;
    final frameOnly = bits.read(1);
    if (frameOnly == 0) bits.read(1); // mb_adaptive_frame_field_flag
    bits.read(1); // direct_8x8_inference_flag
    var cropLeft = 0;
    var cropRight = 0;
    var cropTop = 0;
    var cropBottom = 0;
    if (bits.read(1) != 0) {
      cropLeft = bits.ue(max: 65535);
      cropRight = bits.ue(max: 65535);
      cropTop = bits.ue(max: 65535);
      cropBottom = bits.ue(max: 65535);
    }
    final chromaArray = separateColourPlane ? 0 : chroma;
    final cropUnitX = chromaArray == 1 || chromaArray == 2 ? 2 : 1;
    final cropUnitY = (chromaArray == 1 ? 2 : 1) * (2 - frameOnly);
    final width = columns * 16 - cropUnitX * (cropLeft + cropRight);
    final height =
        rows * 16 * (2 - frameOnly) - cropUnitY * (cropTop + cropBottom);
    if (width < 1 || width > 65535 || height < 1 || height > 65535) {
      throw const FormatException('Invalid cropped H.264 video dimensions.');
    }
    return (width, height);
  }

  static bool _isBSlice(Uint8List nal) {
    final rbsp = <int>[];
    var zeros = 0;
    for (var i = 1; i < nal.length && rbsp.length < 16; i++) {
      final byte = nal[i];
      if (zeros >= 2 && byte == 3) {
        zeros = 0;
        continue;
      }
      rbsp.add(byte);
      zeros = byte == 0 ? zeros + 1 : 0;
    }
    var bit = 0;
    int readBit() {
      if (bit >= rbsp.length * 8) {
        throw const FormatException('Truncated H.264 slice header.');
      }
      return rbsp[bit ~/ 8] >> (7 - bit++ % 8) & 1;
    }

    int ue() {
      var count = 0;
      while (readBit() == 0) {
        if (++count > 31) {
          throw const FormatException('Invalid H.264 slice header.');
        }
      }
      var value = 1;
      for (var i = 0; i < count; i++) {
        value = (value << 1) | readBit();
      }
      return value - 1;
    }

    ue(); // first_mb_in_slice
    final type = ue();
    if (type > 9) throw const FormatException('Invalid H.264 slice type.');
    return type % 5 == 1;
  }

  /// Annex B start codes may be three or four bytes. Reject AVCC/raw packets
  /// rather than silently writing a malformed file under the wrong contract.
  static List<Uint8List> _nals(Uint8List data) {
    final starts = <(int, int)>[];
    for (var i = 0; i + 2 < data.length; i++) {
      if (data[i] != 0 || data[i + 1] != 0) continue;
      if (data[i + 2] == 1) {
        starts.add((i, i + 3));
        i += 2;
      } else if (i + 3 < data.length && data[i + 2] == 0 && data[i + 3] == 1) {
        starts.add((i, i + 4));
        i += 3;
      }
    }
    if (starts.isEmpty || data.take(starts.first.$1).any((b) => b != 0)) {
      throw const FormatException('Expected Annex B H.264 data.');
    }
    final result = <Uint8List>[];
    for (var i = 0; i < starts.length; i++) {
      final start = starts[i].$2;
      var end = i + 1 < starts.length ? starts[i + 1].$1 : data.length;
      while (end > start && data[end - 1] == 0) {
        end--;
      }
      if (start == end || data[start] & 0x80 != 0) {
        throw const FormatException('Invalid H.264 NAL unit.');
      }
      result.add(Uint8List.sublistView(data, start, end));
    }
    return result;
  }

  static Uint8List _ftyp() =>
      _box('ftyp', ['isom'.codeUnits, _u32(512), 'isomiso2avc1mp41'.codeUnits]);
  static Uint8List _u16(int n) =>
      (ByteData(2)..setUint16(0, n)).buffer.asUint8List();
  static Uint8List _u32(int n) =>
      (ByteData(4)..setUint32(0, n)).buffer.asUint8List();
  static Uint8List _u64(int n) =>
      (ByteData(8)..setUint64(0, n)).buffer.asUint8List();
  static Uint8List _join(List<List<int>> parts) {
    final b = BytesBuilder(copy: false);
    for (final part in parts) {
      b.add(part);
    }
    return b.takeBytes();
  }

  static Uint8List _box(String type, List<List<int>> parts) {
    final payload = _join(parts);
    return _join([_u32(payload.length + 8), type.codeUnits, payload]);
  }

  static Uint8List _full(
    String type,
    List<List<int>> parts, {
    int version = 0,
    int flags = 0,
  }) => _box(type, [
    [version, flags >> 16 & 255, flags >> 8 & 255, flags & 255],
    ...parts,
  ]);
  static Uint8List _matrix() => _join([
    for (final n in [0x10000, 0, 0, 0, 0x10000, 0, 0, 0, 0x40000000]) _u32(n),
  ]);

  static Uint8List _moov(
    int width,
    int height,
    Uint8List sps,
    Uint8List pps,
    List<int> sizes,
    List<int> durations,
    List<int> sync,
    int mediaStart,
  ) {
    final duration = durations.fold<int>(0, (a, b) => a + b);
    // Version 1 time headers avoid the ~71-minute overflow at microsecond scale.
    final mvhd = _full('mvhd', [
      _u64(0),
      _u64(0),
      _u32(_timescale),
      _u64(duration),
      _u32(0x10000),
      _u16(0x100),
      Uint8List(10),
      _matrix(),
      Uint8List(24),
      _u32(2),
    ], version: 1);
    final tkhd = _full(
      'tkhd',
      [
        _u64(0),
        _u64(0),
        _u32(1),
        _u32(0),
        _u64(duration),
        Uint8List(8),
        _u16(0),
        _u16(0),
        _u16(0),
        _u16(0),
        _matrix(),
        _u32(width << 16),
        _u32(height << 16),
      ],
      version: 1,
      flags: 3,
    );
    final mdhd = _full('mdhd', [
      _u64(0),
      _u64(0),
      _u32(_timescale),
      _u64(duration),
      _u16(0x55c4),
      _u16(0),
    ], version: 1);
    final hdlr = _full('hdlr', [
      _u32(0),
      'vide'.codeUnits,
      Uint8List(12),
      'OpenPelo Video\x00'.codeUnits,
    ]);
    final avcc = _box('avcC', [
      [1, sps[1], sps[2], sps[3], 255, 225],
      _u16(sps.length),
      sps,
      [1],
      _u16(pps.length),
      pps,
    ]);
    final avc1 = _box('avc1', [
      Uint8List(6),
      _u16(1),
      Uint8List(16),
      _u16(width),
      _u16(height),
      _u32(0x480000),
      _u32(0x480000),
      _u32(0),
      _u16(1),
      Uint8List(32),
      _u16(24),
      _u16(0xffff),
      avcc,
    ]);
    final runs = <(int, int)>[];
    for (final d in durations) {
      if (runs.isNotEmpty && runs.last.$2 == d) {
        runs[runs.length - 1] = (runs.last.$1 + 1, d);
      } else {
        runs.add((1, d));
      }
    }
    // All samples form one contiguous chunk, so a single 64-bit chunk offset
    // supports large recordings without a per-frame offset table.
    final stbl = _box('stbl', [
      _full('stsd', [_u32(1), avc1]),
      _full('stts', [
        _u32(runs.length),
        for (final run in runs) ...[_u32(run.$1), _u32(run.$2)],
      ]),
      _full('stsc', [_u32(1), _u32(1), _u32(sizes.length), _u32(1)]),
      _full('stsz', [
        _u32(0),
        _u32(sizes.length),
        for (final size in sizes) _u32(size),
      ]),
      _full('co64', [_u32(1), _u64(mediaStart)]),
      _full('stss', [
        _u32(sync.length),
        for (final sample in sync) _u32(sample),
      ]),
    ]);
    final dinf = _box('dinf', [
      _full('dref', [_u32(1), _full('url ', [], flags: 1)]),
    ]);
    final minf = _box('minf', [
      _full('vmhd', [Uint8List(8)], flags: 1),
      dinf,
      stbl,
    ]);
    return _box('moov', [
      mvhd,
      _box('trak', [
        tkhd,
        _box('mdia', [mdhd, hdlr, minf]),
      ]),
    ]);
  }
}

/// Bounded RBSP reader shared by SPS fields; skips emulation-prevention bytes.
class _H264Bits {
  _H264Bits(Uint8List nal) {
    if (nal.length < 5 || nal.length > 65535) {
      throw const FormatException('Invalid H.264 SPS length.');
    }
    var zeros = 0;
    for (var i = 1; i < nal.length; i++) {
      final byte = nal[i];
      if (zeros >= 2 && byte == 3) {
        if (i + 1 >= nal.length || nal[i + 1] > 3) {
          throw const FormatException('Invalid H.264 emulation prevention.');
        }
        zeros = 0;
        continue;
      }
      _bytes.add(byte);
      zeros = byte == 0 ? zeros + 1 : 0;
    }
  }
  final List<int> _bytes = [];
  int _position = 0;
  int read(int count) {
    if (_position + count > _bytes.length * 8) {
      throw const FormatException('Truncated H.264 SPS.');
    }
    var result = 0;
    for (var i = 0; i < count; i++) {
      result =
          (result << 1) | ((_bytes[_position ~/ 8] >> (7 - _position % 8)) & 1);
      _position++;
    }
    return result;
  }

  int ue({int max = 0x7fffffff}) {
    var zeros = 0;
    while (read(1) == 0) {
      if (++zeros > 31) {
        throw const FormatException('Invalid H.264 exponential code.');
      }
    }
    final value = (1 << zeros) - 1 + read(zeros);
    if (value > max) {
      throw const FormatException('H.264 SPS field exceeds its limit.');
    }
    return value;
  }

  int se() {
    final value = ue();
    return value.isOdd ? (value + 1) ~/ 2 : -(value ~/ 2);
  }
}
