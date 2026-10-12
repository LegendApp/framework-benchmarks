import Foundation

enum JSONRangeKind {
  case array
  case object
  case primitive
  case string
}

struct JSONRangeValue {
  let end: Int
  let kind: JSONRangeKind
  let reader: JSONRangeReader
  let start: Int

  subscript(key: String) -> JSONRangeValue? { reader.member(self, key: key) }

  var arrayValues: [JSONRangeValue]? {
    guard kind == .array else { return nil }
    var values: [JSONRangeValue] = []
    return reader.forEachArrayValue(self) {
      values.append($0)
      return true
    } ? values : nil
  }

  var objectMembers: [(String, JSONRangeValue)]? {
    guard kind == .object else { return nil }
    var values: [(String, JSONRangeValue)] = []
    return reader.forEachObjectMember(self) { key, value in
      values.append((reader.stringValue(key), value))
      return true
    } ? values : nil
  }
}

struct JSONRangeReader {
  let bytes: UnsafeRawBufferPointer
  var source: Data? = nil

  func topLevelObject(_ range: Range<Int>) -> JSONRangeValue? {
    let start = skipWhitespace(range.lowerBound, end: range.upperBound)
    var end = min(range.upperBound, bytes.count)
    while end > start, isWhitespace(bytes[end - 1]) { end -= 1 }
    guard start < end, bytes[start] == 123, bytes[end - 1] == 125 else { return nil }
    return JSONRangeValue(end: end, kind: .object, reader: self, start: start)
  }

  // Match RN's two known envelope orders. Unrecognized orders use the general
  // member scan; ignored payloads on the known path need no recursive traversal.
  func codexEnvelope(_ object: JSONRangeValue) -> [String: JSONRangeValue]? {
    var cursor = object.start + 1
    if let timestamp = orderedMember(object, cursor: &cursor, key: "timestamp") {
      _ = orderedMember(object, cursor: &cursor, key: "ordinal")
      if let type = orderedMember(object, cursor: &cursor, key: "type"),
        let payload = trailingMember(object, cursor: cursor, key: "payload")
      {
        return ["timestamp": timestamp, "type": type, "payload": payload]
      }
    }
    guard let members = object.objectMembers else { return nil }
    return Dictionary(members, uniquingKeysWith: { _, latest in latest })
  }

  private func memberStart(_ position: Int, end: Int, key: String) -> Int? {
    let start = skipWhitespace(position, end: end)
    guard let keyEnd = skipString(start, end: end),
      stringEquals(JSONRangeValue(end: keyEnd, kind: .string, reader: self, start: start), key)
    else { return nil }
    let colon = skipWhitespace(keyEnd, end: end)
    guard colon < end, bytes[colon] == 58 else { return nil }
    return skipWhitespace(colon + 1, end: end)
  }

  private func orderedMember(_ object: JSONRangeValue, cursor: inout Int, key: String)
    -> JSONRangeValue?
  {
    guard let start = memberStart(cursor, end: object.end, key: key),
      let end = skipValue(start, end: object.end)
    else { return nil }
    let separator = skipWhitespace(end, end: object.end)
    guard separator < object.end, bytes[separator] == 44 else { return nil }
    cursor = separator + 1
    return value(start: start, end: end)
  }

  private func trailingMember(_ object: JSONRangeValue, cursor: Int, key: String) -> JSONRangeValue?
  {
    guard let start = memberStart(cursor, end: object.end, key: key) else { return nil }
    var end = object.end - 1
    while end > start, isWhitespace(bytes[end - 1]) { end -= 1 }
    guard let result = value(start: start, end: end) else { return nil }
    switch result.kind {
    case .object: guard bytes[end - 1] == 125 else { return nil }
    case .array: guard bytes[end - 1] == 93 else { return nil }
    case .string: guard bytes[end - 1] == 34 else { return nil }
    case .primitive: break
    }
    return result
  }

  func validatedObject(_ range: Range<Int>) -> JSONRangeValue? {
    guard let object = topLevelObject(range), skipValue(object.start, end: object.end) == object.end
    else { return nil }
    return object
  }

  func member(_ object: JSONRangeValue, key: String) -> JSONRangeValue? {
    guard let start = findMemberStart(object, key: key), let end = skipValue(start, end: object.end)
    else { return nil }
    return value(start: start, end: end)
  }

  func memberKind(_ object: JSONRangeValue, key: String) -> JSONRangeKind? {
    guard let start = findMemberStart(object, key: key) else { return nil }
    return value(start: start, end: object.end)?.kind
  }

  private func findMemberStart(_ object: JSONRangeValue, key: String) -> Int? {
    guard object.kind == .object, object.end <= bytes.count, object.end > object.start + 1 else {
      return nil
    }
    var cursor = object.start + 1
    while cursor < object.end - 1 {
      cursor = skipWhitespace(cursor, end: object.end)
      guard cursor < object.end, bytes[cursor] != 125 else { return nil }
      let keyStart = cursor
      guard let keyEnd = skipString(cursor, end: object.end) else { return nil }
      cursor = skipWhitespace(keyEnd, end: object.end)
      guard cursor < object.end, bytes[cursor] == 58 else { return nil }
      cursor = skipWhitespace(cursor + 1, end: object.end)
      let keyValue = JSONRangeValue(end: keyEnd, kind: .string, reader: self, start: keyStart)
      if stringEquals(keyValue, key) { return cursor }
      guard let valueEnd = skipValue(cursor, end: object.end) else { return nil }
      cursor = skipWhitespace(valueEnd, end: object.end)
      guard cursor < object.end, bytes[cursor] == 44 else { return nil }
      cursor += 1
    }
    return nil
  }

  func forEachArrayValue(
    _ array: JSONRangeValue,
    _ body: (JSONRangeValue) -> Bool
  ) -> Bool {
    guard array.kind == .array, array.end <= bytes.count, array.end > array.start + 1 else {
      return false
    }
    var cursor = array.start + 1
    while cursor < array.end - 1 {
      cursor = skipWhitespace(cursor, end: array.end)
      if bytes[cursor] == 93 { break }
      guard let end = skipValue(cursor, end: array.end), let item = value(start: cursor, end: end)
      else { return false }
      if !body(item) { return true }
      cursor = skipWhitespace(end, end: array.end)
      if cursor < array.end, bytes[cursor] == 44 {
        cursor += 1
      } else if cursor >= array.end || bytes[cursor] != 93 {
        return false
      }
    }
    return true
  }

  func forEachObjectMember(
    _ object: JSONRangeValue,
    _ body: (JSONRangeValue, JSONRangeValue) -> Bool
  ) -> Bool {
    guard object.kind == .object, object.end <= bytes.count, object.end > object.start + 1 else {
      return false
    }
    var cursor = object.start + 1
    while cursor < object.end - 1 {
      cursor = skipWhitespace(cursor, end: object.end)
      if bytes[cursor] == 125 { break }
      let keyStart = cursor
      guard let keyEnd = skipString(cursor, end: object.end) else { return false }
      cursor = skipWhitespace(keyEnd, end: object.end)
      guard cursor < object.end, bytes[cursor] == 58 else { return false }
      cursor = skipWhitespace(cursor + 1, end: object.end)
      guard let end = skipValue(cursor, end: object.end),
        let value = value(start: cursor, end: end)
      else { return false }
      let key = JSONRangeValue(end: keyEnd, kind: .string, reader: self, start: keyStart)
      if !body(key, value) { return true }
      cursor = skipWhitespace(end, end: object.end)
      if cursor < object.end, bytes[cursor] == 44 {
        cursor += 1
      } else if cursor >= object.end || bytes[cursor] != 125 {
        return false
      }
    }
    return true
  }

  func boolValue(_ value: JSONRangeValue?, fallback: Bool = false) -> Bool {
    guard let value, value.kind == .primitive else { return fallback }
    if rawEquals(value.start..<value.end, "true") { return true }
    if rawEquals(value.start..<value.end, "false") { return false }
    return fallback
  }

  func numberValue(_ value: JSONRangeValue?, fallback: Double = 0) -> Double {
    guard let value, value.kind == .primitive else { return fallback }
    return Double(rawString(value.start..<value.end)) ?? fallback
  }

  func stringValue(_ value: JSONRangeValue?) -> String {
    guard let value, value.kind == .string, value.end >= value.start + 2 else { return "" }
    let content = (value.start + 1)..<(value.end - 1)
    var cursor = content.lowerBound
    while cursor < content.upperBound, bytes[cursor] != 92 { cursor += 1 }
    if cursor == content.upperBound { return rawString(content) }

    var output: [UInt8] = []
    output.reserveCapacity(content.count)
    cursor = content.lowerBound
    while cursor < content.upperBound {
      let byte = bytes[cursor]
      cursor += 1
      if byte != 92 {
        output.append(byte)
        continue
      }
      guard cursor < content.upperBound else { break }
      let escaped = bytes[cursor]
      cursor += 1
      switch escaped {
      case 34, 47, 92: output.append(escaped)
      case 98: output.append(8)
      case 102: output.append(12)
      case 110: output.append(10)
      case 114: output.append(13)
      case 116: output.append(9)
      case 117:
        guard let high = hexCodeUnit(at: cursor, end: content.upperBound) else {
          appendUTF8(0xfffd, to: &output)
          continue
        }
        cursor += 4
        var codepoint = UInt32(high)
        if (0xd800...0xdbff).contains(high), cursor + 6 <= content.upperBound,
          bytes[cursor] == 92, bytes[cursor + 1] == 117,
          let low = hexCodeUnit(at: cursor + 2, end: content.upperBound),
          (0xdc00...0xdfff).contains(low)
        {
          codepoint = 0x10000 + (UInt32(high - 0xd800) << 10) + UInt32(low - 0xdc00)
          cursor += 6
        }
        appendUTF8(codepoint, to: &output)
      default: output.append(escaped)
      }
    }
    return String(decoding: output, as: UTF8.self)
  }

  private func skipWhitespace(_ position: Int, end: Int) -> Int {
    var cursor = position
    while cursor < min(end, bytes.count), isWhitespace(bytes[cursor]) { cursor += 1 }
    return cursor
  }

  private func skipString(_ position: Int, end: Int) -> Int? {
    let limit = min(end, bytes.count)
    guard position < limit, bytes[position] == 34 else { return nil }
    var cursor = position + 1
    while cursor < limit {
      let byte = bytes[cursor]
      cursor += 1
      if byte == 34 { return cursor }
      if byte == 92 {
        guard cursor < limit else { return nil }
        cursor += 1
      } else if byte < 32 {
        return nil
      }
    }
    return nil
  }

  private func skipValue(_ position: Int, end: Int) -> Int? {
    let limit = min(end, bytes.count)
    var cursor = skipWhitespace(position, end: limit)
    guard cursor < limit else { return nil }
    if bytes[cursor] == 34 { return skipString(cursor, end: limit) }
    if bytes[cursor] == 123 || bytes[cursor] == 91 {
      let opening = bytes[cursor]
      let closing: UInt8 = opening == 123 ? 125 : 93
      cursor += 1
      while cursor < limit {
        cursor = skipWhitespace(cursor, end: limit)
        guard cursor < limit else { return nil }
        if bytes[cursor] == closing { return cursor + 1 }
        if opening == 123 {
          guard let keyEnd = skipString(cursor, end: limit) else { return nil }
          cursor = skipWhitespace(keyEnd, end: limit)
          guard cursor < limit, bytes[cursor] == 58 else { return nil }
          cursor += 1
        }
        guard let valueEnd = skipValue(cursor, end: limit) else { return nil }
        cursor = skipWhitespace(valueEnd, end: limit)
        if cursor < limit, bytes[cursor] == 44 {
          cursor += 1
        } else if cursor < limit, bytes[cursor] == closing {
          return cursor + 1
        } else {
          return nil
        }
      }
      return nil
    }
    let start = cursor
    while cursor < limit, !isPrimitiveTerminator(bytes[cursor]) { cursor += 1 }
    return cursor > start ? cursor : nil
  }

  private func value(start: Int, end: Int) -> JSONRangeValue? {
    guard start < end, start < bytes.count else { return nil }
    let kind: JSONRangeKind =
      switch bytes[start] {
      case 34: .string
      case 91: .array
      case 123: .object
      default: .primitive
      }
    return JSONRangeValue(end: end, kind: kind, reader: self, start: start)
  }

  @inline(__always)
  private func isWhitespace(_ byte: UInt8) -> Bool {
    byte == 9 || byte == 10 || byte == 13 || byte == 32
  }

  @inline(__always)
  private func isPrimitiveTerminator(_ byte: UInt8) -> Bool {
    isWhitespace(byte) || byte == 44 || byte == 93 || byte == 125
  }

  private func stringEquals(_ value: JSONRangeValue, _ expected: String) -> Bool {
    guard value.kind == .string, value.end >= value.start + 2 else { return false }
    let range = (value.start + 1)..<(value.end - 1)
    if range.contains(where: { bytes[$0] == 92 }) { return stringValue(value) == expected }
    return rawEquals(range, expected)
  }

  private func rawEquals(_ range: Range<Int>, _ expected: String) -> Bool {
    let expectedBytes = Array(expected.utf8)
    guard range.count == expectedBytes.count else { return false }
    for (offset, byte) in expectedBytes.enumerated() where bytes[range.lowerBound + offset] != byte
    {
      return false
    }
    return true
  }

  private func rawString(_ range: Range<Int>) -> String {
    guard let baseAddress = bytes.baseAddress else { return "" }
    let start = baseAddress.assumingMemoryBound(to: UInt8.self).advanced(by: range.lowerBound)
    return String(decoding: UnsafeBufferPointer(start: start, count: range.count), as: UTF8.self)
  }

  private func hexCodeUnit(at start: Int, end: Int) -> UInt16? {
    guard start + 4 <= end else { return nil }
    var value: UInt16 = 0
    for byte in bytes[start..<(start + 4)] {
      let nibble: UInt16
      switch byte {
      case 48...57: nibble = UInt16(byte - 48)
      case 65...70: nibble = UInt16(byte - 55)
      case 97...102: nibble = UInt16(byte - 87)
      default: return nil
      }
      value = (value << 4) | nibble
    }
    return value
  }

  private func appendUTF8(_ codepoint: UInt32, to output: inout [UInt8]) {
    if codepoint <= 0x7f {
      output.append(UInt8(codepoint))
    } else if codepoint <= 0x7ff {
      output += [UInt8(0xc0 | codepoint >> 6), UInt8(0x80 | codepoint & 0x3f)]
    } else if codepoint <= 0xffff {
      output += [
        UInt8(0xe0 | codepoint >> 12), UInt8(0x80 | codepoint >> 6 & 0x3f),
        UInt8(0x80 | codepoint & 0x3f),
      ]
    } else {
      output += [
        UInt8(0xf0 | codepoint >> 18), UInt8(0x80 | codepoint >> 12 & 0x3f),
        UInt8(0x80 | codepoint >> 6 & 0x3f), UInt8(0x80 | codepoint & 0x3f),
      ]
    }
  }
}
