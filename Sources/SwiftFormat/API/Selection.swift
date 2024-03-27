//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import SwiftSyntax

/// The selection as given on the command line - an array of offets and lengths
public struct Selection {
  // TODO: make this a typealias instead
  public struct Range: Decodable {
    public let offset: AbsolutePosition
    public let length: Int
    public var end: AbsolutePosition { offset.advanced(by: length) }

    public init(from decoder: any Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      offset = AbsolutePosition(utf8Offset: try container.decode(Int.self, forKey: .offset))
      length = try container.decode(Int.self, forKey: .length)
    }

    public init(start: AbsolutePosition, end: AbsolutePosition) {
      offset = start
      length = end.utf8Offset - start.utf8Offset
    }

    public init(start: Int, end: Int) {
      offset = AbsolutePosition(utf8Offset: start)
      length = end - start
    }

    enum CodingKeys: CodingKey {
      case offset
      case length
    }
  }

  public let ranges: [Range]

  public init?(json: String) {
    guard let data = json.data(using: .utf8),
          let ranges = try? JSONDecoder().decode([Range].self, from: data) else {
      return nil
    }
    self.ranges = ranges
  }

  public init(ranges: [Selection.Range]) {
    self.ranges = ranges
  }

  public func contains(_ position: AbsolutePosition) -> Bool {
    return ranges.contains { return $0.offset <= position && position < $0.end }
  }

  public func overlaps(_ range: Range) -> Bool {
    return ranges.contains {
      let maxStart = max($0.offset, range.offset)
      let minEnd = (min($0.end, range.end))
      return maxStart <= minEnd
    }
  }
}


public extension Syntax {
  /// return true if the node is completely inside any range in the selection (or if there's
  /// no selection)
  func isInsideSelection(_ selection: Selection?) -> Bool {
    // no selection means we should process everything
    guard let selection else { return true }

    return selection.ranges.contains { range in
      return range.offset <= position && endPosition <= range.end
    }
  }
}
