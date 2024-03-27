//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftSyntax
import SwiftFormat

/// Encapsulates the locations of emoji markers extracted from source text.
public struct MarkedText {
  /// A mapping from marker names to the UTF-8 offset where the marker was found in the string.
  public let markers: [String: Int]

  /// The text with all markers removed.
  public let textWithoutMarkers: String

  /// If the marked text contains "➡️" and "⬅️", they're used to create a selection
  public var selection: Selection?

  /// Creates a new `MarkedText` value by extracting emoji markers from the given text.
  public init(textWithMarkers markedText: String) {
    var text = ""
    var markers = [String: Int]()
    var lastIndex = markedText.startIndex
    var ranges = [Selection.Range]()
    var lastRangeStart = 0
    for marker in findMarkedRanges(in: markedText) {
      text += markedText[lastIndex..<marker.range.lowerBound]
      lastIndex = marker.range.upperBound

      if marker.name == "➡️" {
        lastRangeStart = text.utf8.count
      } else if marker.name == "⬅️" {
        ranges.append(Selection.Range(start: lastRangeStart, end: text.utf8.count))
      } else {
        assert(markers[marker.name] == nil, "Marker names must be unique")
        markers[marker.name] = text.utf8.count
      }
    }

    text += markedText[lastIndex..<markedText.endIndex]

    self.markers = markers
    self.textWithoutMarkers = text
    if !ranges.isEmpty {
      selection = Selection(ranges: ranges)
    }
  }
}

private struct Marker {
  /// The name (i.e., emoji identifier) of the marker.
  var name: String

  /// The range of the marker.
  ///
  /// If the marker contains all the non-whitespace characters on the line, then this is the range
  /// of the entire line. Otherwise, it's the range of the marker itself.
  var range: Range<String.Index>
}

private func findMarkedRanges(in text: String) -> [Marker] {
  var markers = [Marker]()
  while let marker = nextMarkedRange(in: text, from: markers.last?.range.upperBound ?? text.startIndex) {
    markers.append(marker)
  }
  return markers
}

private func nextMarkedRange(in text: String, from index: String.Index) -> Marker? {
  guard let start = text[index...].firstIndex(where: { $0.isMarkerEmoji }) else {
    return nil
  }

  let end = text.index(after: start)
  let markerRange = start..<end
  let name = String(text[start..<end])
  return Marker(name: name, range: markerRange)
}

extension Character {
  /// A value indicating whether or not the character is an emoji that we recognize as a source
  /// location marker.
  fileprivate var isMarkerEmoji: Bool {
    switch self {
    case "0️⃣", "1️⃣", "2️⃣", "3️⃣", "4️⃣", "5️⃣", "6️⃣", "7️⃣", "8️⃣", "9️⃣", "🔟", "ℹ️", "➡️", "⬅️":
      return true
    default: return false
    }
  }
}
