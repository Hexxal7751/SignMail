import 'dart:convert';
import 'dart:typed_data';

/// A problem found while reading ASN.1 / DER / BER data.
class Asn1Exception implements Exception {
  const Asn1Exception(this.message);

  final String message;

  @override
  String toString() => 'ASN.1: $message';
}

/// One tag-length-value element of DER/BER data (a small, dependency-free
/// reader that also understands BER "indefinite length" used by some mail
/// programs).
class Tlv {
  Tlv._(
    this.data,
    this.offset,
    this.tag,
    this.headerLength,
    this.valueLength,
    this.indefinite,
  );

  final Uint8List data;
  final int offset;
  final int tag;
  final int headerLength;
  final int valueLength;
  final bool indefinite;

  static const int tagInteger = 0x02;
  static const int tagBitString = 0x03;
  static const int tagOctetString = 0x04;
  static const int tagNull = 0x05;
  static const int tagOid = 0x06;
  static const int tagUtf8 = 0x0C;
  static const int tagSequence = 0x30;
  static const int tagSet = 0x31;

  /// Reads one element starting at [offset].
  static Tlv parse(Uint8List data, [int offset = 0, int? limit]) {
    return _parseAt(data, offset, limit ?? data.length, 0);
  }

  static Tlv _parseAt(Uint8List data, int offset, int limit, int depth) {
    if (depth > 40) {
      throw const Asn1Exception('nesting too deep');
    }
    if (offset + 2 > limit) {
      throw const Asn1Exception('truncated element');
    }

    final tag = data[offset];
    if ((tag & 0x1F) == 0x1F) {
      throw const Asn1Exception('high tag numbers are not supported');
    }

    var pos = offset + 1;
    final first = data[pos++];
    var length = 0;
    var indefinite = false;

    if (first < 0x80) {
      length = first;
    } else if (first == 0x80) {
      if ((tag & 0x20) == 0) {
        throw const Asn1Exception('indefinite length on a primitive');
      }
      indefinite = true;
    } else {
      final count = first & 0x7F;
      if (count > 4 || pos + count > limit) {
        throw const Asn1Exception('bad length');
      }
      for (var i = 0; i < count; i++) {
        length = (length << 8) | data[pos++];
      }
    }

    final headerLength = pos - offset;

    if (indefinite) {
      var cursor = pos;
      while (true) {
        if (cursor + 2 > limit) {
          throw const Asn1Exception('missing end-of-contents');
        }
        if (data[cursor] == 0 && data[cursor + 1] == 0) {
          break;
        }
        final child = _parseAt(data, cursor, limit, depth + 1);
        cursor = child.end;
      }
      return Tlv._(data, offset, tag, headerLength, cursor - pos, true);
    }

    if (pos + length > limit) {
      throw const Asn1Exception('element longer than its container');
    }
    return Tlv._(data, offset, tag, headerLength, length, false);
  }

  bool get constructed => (tag & 0x20) != 0;
  int get tagClass => tag >> 6;
  int get tagNumber => tag & 0x1F;
  bool get isContext => tagClass == 2;

  int get valueStart => offset + headerLength;
  int get valueEnd => valueStart + valueLength;
  int get end => indefinite ? valueEnd + 2 : valueEnd;

  /// The whole element as it appeared (tag, length and value).
  Uint8List get encoded => Uint8List.sublistView(data, offset, end);

  /// The content bytes only.
  Uint8List get value => Uint8List.sublistView(data, valueStart, valueEnd);

  /// The direct children of a constructed element.
  List<Tlv> get children {
    final result = <Tlv>[];
    var pos = valueStart;
    final stop = valueEnd;
    while (pos < stop) {
      final child = _parseAt(data, pos, stop, 1);
      result.add(child);
      pos = child.end;
    }
    return result;
  }

  Tlv child(int index) {
    final list = children;
    if (index >= list.length) {
      throw const Asn1Exception('missing element');
    }
    return list[index];
  }

  /// The decoded object identifier (dotted form).
  String get oid {
    if (tag != tagOid) {
      throw const Asn1Exception('not an OBJECT IDENTIFIER');
    }
    final bytes = value;
    if (bytes.isEmpty) {
      throw const Asn1Exception('empty OBJECT IDENTIFIER');
    }
    final parts = <int>[];
    final firstValue = bytes[0];
    if (firstValue < 40) {
      parts
        ..add(0)
        ..add(firstValue);
    } else if (firstValue < 80) {
      parts
        ..add(1)
        ..add(firstValue - 40);
    } else {
      parts
        ..add(2)
        ..add(firstValue - 80);
    }
    var current = 0;
    for (var i = 1; i < bytes.length; i++) {
      current = (current << 7) | (bytes[i] & 0x7F);
      if ((bytes[i] & 0x80) == 0) {
        parts.add(current);
        current = 0;
      }
    }
    return parts.join('.');
  }

  /// The INTEGER value (two's complement).
  BigInt get integer {
    if (tag != tagInteger) {
      throw const Asn1Exception('not an INTEGER');
    }
    return bytesToBigInt(value, signed: true);
  }

  /// The content of an OCTET STRING, including the constructed (chunked)
  /// BER form.
  Uint8List get octets {
    if (!constructed) {
      return value;
    }
    final builder = BytesBuilder(copy: false);
    for (final part in children) {
      builder.add(part.octets);
    }
    return builder.toBytes();
  }

  /// The bytes of a BIT STRING without the "unused bits" prefix.
  Uint8List get bitStringBytes {
    final bytes = value;
    if (bytes.isEmpty) {
      return bytes;
    }
    return Uint8List.sublistView(bytes, 1);
  }

  /// Text of the common string types.
  String get text {
    switch (tag) {
      case 0x1E: // BMPString
        final bytes = value;
        final units = <int>[];
        for (var i = 0; i + 1 < bytes.length; i += 2) {
          units.add((bytes[i] << 8) | bytes[i + 1]);
        }
        return String.fromCharCodes(units);
      case 0x0C: // UTF8String
        return utf8.decode(value, allowMalformed: true);
      default: // Printable, IA5, Teletex and friends
        return latin1.decode(value);
    }
  }

  /// UTCTime or GeneralizedTime as a UTC [DateTime].
  DateTime get time {
    final raw = latin1.decode(value);
    final digits = RegExp(r'^(\d+)');
    final match = digits.firstMatch(raw);
    if (match == null) {
      throw const Asn1Exception('bad time');
    }
    final d = match.group(1)!;
    int n(int start, int len) => int.parse(d.substring(start, start + len));

    if (tag == 0x17) {
      if (d.length < 10) {
        throw const Asn1Exception('bad UTCTime');
      }
      var year = n(0, 2);
      year += year >= 50 ? 1900 : 2000;
      return DateTime.utc(
        year,
        n(2, 2),
        n(4, 2),
        n(6, 2),
        n(8, 2),
        d.length >= 12 ? n(10, 2) : 0,
      );
    }
    if (tag == 0x18) {
      if (d.length < 12) {
        throw const Asn1Exception('bad GeneralizedTime');
      }
      return DateTime.utc(
        n(0, 4),
        n(4, 2),
        n(6, 2),
        n(8, 2),
        n(10, 2),
        d.length >= 14 ? n(12, 2) : 0,
      );
    }
    throw const Asn1Exception('not a time');
  }
}

/// Converts big-endian bytes to a [BigInt].
BigInt bytesToBigInt(List<int> bytes, {bool signed = false}) {
  if (bytes.isEmpty) {
    return BigInt.zero;
  }
  var result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b);
  }
  if (signed && (bytes[0] & 0x80) != 0) {
    result -= BigInt.one << (bytes.length * 8);
  }
  return result;
}

/// Lower-case hex text of [bytes].
String toHex(List<int> bytes) {
  final buffer = StringBuffer();
  for (final b in bytes) {
    buffer.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

/// True when both lists hold the same bytes.
bool sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}