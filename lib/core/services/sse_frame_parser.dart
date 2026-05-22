/// A single decoded Server-Sent Events frame.
///
/// SSE frames are line-oriented: `field: value` lines accumulate until a blank
/// line dispatches the frame. A line starting with `:` is a comment (the
/// backend sends `:ping` keepalives) — comments are surfaced as standalone
/// frames with [isComment] `true` so the caller can ignore them explicitly.
class SseFrame {
  /// The `event:` field, or `null` when the frame carried none.
  final String? event;

  /// All `data:` lines joined with `\n`. Empty string when there was no data.
  final String data;

  /// The `id:` field, or `null` when absent.
  final String? id;

  /// `true` for `:`-comment frames (e.g. `:ping` keepalives).
  final bool isComment;

  const SseFrame({
    this.event,
    this.data = '',
    this.id,
    this.isComment = false,
  });
}

/// Incremental SSE frame parser. Feed raw decoded text chunks via [addChunk];
/// it buffers partial lines across chunk boundaries and returns whole frames
/// as they complete. It never throws on malformed input.
class SseFrameParser {
  String _lineBuffer = '';
  String? _event;
  final List<String> _dataLines = [];
  String? _id;
  bool _hasField = false;

  /// Feeds one decoded chunk and returns every frame completed by it. A chunk
  /// may contain zero, partial, or many frames.
  List<SseFrame> addChunk(String chunk) {
    final frames = <SseFrame>[];

    // Normalize line endings. CR / LF only ever terminate lines in SSE — they
    // never appear inside field content — so a blanket replace is safe even if
    // a `\r\n` pair is split across two chunks (the stray blank line it could
    // produce yields an empty frame, which is dropped below).
    final combined = (_lineBuffer + chunk)
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final parts = combined.split('\n');

    // The final element is whatever came after the last newline — an
    // incomplete line. Hold it for the next chunk.
    _lineBuffer = parts.removeLast();

    for (final line in parts) {
      if (line.isEmpty) {
        final frame = _buildFrame();
        if (frame != null) frames.add(frame);
        _resetAccumulator();
        continue;
      }
      if (line.startsWith(':')) {
        // Comment line — self-contained, dispatched immediately.
        frames.add(SseFrame(data: line.substring(1).trimLeft(), isComment: true));
        continue;
      }
      _parseField(line);
    }
    return frames;
  }

  void _parseField(String line) {
    final colon = line.indexOf(':');
    final String field;
    String value;
    if (colon == -1) {
      field = line;
      value = '';
    } else {
      field = line.substring(0, colon);
      value = line.substring(colon + 1);
      if (value.startsWith(' ')) value = value.substring(1);
    }
    switch (field) {
      case 'event':
        _event = value;
        _hasField = true;
      case 'data':
        _dataLines.add(value);
        _hasField = true;
      case 'id':
        _id = value;
        _hasField = true;
      default:
        // Unknown field (e.g. `retry`) — ignored per the SSE spec.
        break;
    }
  }

  SseFrame? _buildFrame() {
    if (!_hasField) return null;
    return SseFrame(
      event: _event,
      data: _dataLines.join('\n'),
      id: _id,
    );
  }

  void _resetAccumulator() {
    _event = null;
    _dataLines.clear();
    _id = null;
    _hasField = false;
  }

  /// Drops all buffered partial state. Call before reconnecting so a half-read
  /// line from a dead connection cannot corrupt the next stream.
  void reset() {
    _lineBuffer = '';
    _resetAccumulator();
  }
}
