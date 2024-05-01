//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2019 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import Markdown
import SwiftSyntax

extension StringProtocol {
  /// Trims whitespace from the end of a string, returning a new string with no trailing whitespace.
  ///
  /// If the string is only whitespace, an empty string is returned.
  ///
  /// - Returns: The string with trailing whitespace removed.
  func trimmingTrailingWhitespace() -> String {
    if isEmpty { return String() }
    let scalars = unicodeScalars
    var idx = scalars.index(before: scalars.endIndex)
    while scalars[idx].properties.isWhitespace {
      if idx == scalars.startIndex { return String() }
      idx = scalars.index(before: idx)
    }
    return String(String.UnicodeScalarView(scalars[...idx]))
  }

  /// Trims whitespace from the beginning of a string, returning a new string with no leading whitespace.
  ///
  /// If the string is only whitespace, an empty string is returned.
  ///
  /// - Returns: The string with trailing whitespace removed.
  func trimmingLeadingWhitespace() -> String {
    if isEmpty { return String() }
    let scalars = unicodeScalars
    var idx = scalars.index(before: scalars.endIndex)
    while scalars[idx].properties.isWhitespace {
      if idx == scalars.startIndex { return String() }
      idx = scalars.index(before: idx)
    }
    return String(String.UnicodeScalarView(scalars[...idx]))
  }

  func trim() -> Self.SubSequence? {
    guard let startIdx = self.firstIndex(where: { !$0.isWhitespace }),
          let lastIdx = self.lastIndex(where: { !$0.isWhitespace }) else {
      return nil
    }
    return self[startIdx...lastIdx]
  }

}



struct Comment {
  enum Kind {
    case line, docLine, block, docBlock

    /// The length of the characters starting the comment.
    var prefixLength: Int {
      switch self {
      // `//`, `/*`
      case .line, .block: return 2
      // `///`, `/**`
      case .docLine, .docBlock: return 3
      }
    }

    var prefix: String {
      switch self {
      case .line: return "//"
      case .block: return "/*"
      case .docBlock: return "/**"
      case .docLine: return "///"
      }
    }
  }

  let kind: Kind
  var text: [String]
  var length: Int

  init(kind: Kind, text: String) {
    self.kind = kind

    switch kind {
    case .line, .docLine:
      self.text = [text.trimmingTrailingWhitespace()]
      self.text[0].removeFirst(kind.prefixLength)
      self.length = self.text.reduce(0, { $0 + $1.count + kind.prefixLength + 1 })

    case .block, .docBlock:
      var fulltext: String = text
      fulltext.removeFirst(kind.prefixLength)
      fulltext.removeLast(2)
      let lines = fulltext.split(separator: "\n", omittingEmptySubsequences: false)

      // The last line in a block style comment contains the "*/" pattern to end the comment. The
      // trailing space(s) need to be kept in that line to have space between text and "*/".
      var trimmedLines = lines.dropLast().map({ $0.trimmingTrailingWhitespace() })
      if let lastLine = lines.last {
        trimmedLines.append(String(lastLine))
      }
      self.text = trimmedLines
      self.length = self.text.reduce(0, { $0 + $1.count }) + kind.prefixLength + 3
    }
  }

  func print(indent: [Indent], width: Int, useMarkdown: Bool) -> String {
    switch self.kind {
    case .line:
      let separator = "\n" + kind.prefix + indent.indentation()
      return kind.prefix + self.text.joined(separator: separator)

    case .docLine:
      if !useMarkdown {
        let indentation = indent.indentation()
        let usableWidth = width - indentation.count
        let lineLimit = MarkupFormatter.Options.PreferredLineLimit(maxLength: usableWidth, breakWith: .softBreak)
        let document = Document(parsing: self.text.joined(separator: "\n"))
        let options = MarkupFormatter.Options(preferredLineLimit: lineLimit, customLinePrefix: kind.prefix + " ")
        // FIXME this can't stay, just annoyed by changing to smart quotes
        let output = document.format(options: options).replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
        // because of the customLinePrefix, blank comment lines have a single space that we should remove
        let lines = output.split(separator: "\n").map { $0.trimmingTrailingWhitespace() }
        return String(lines.joined(separator: "\n" + indentation))
      } else {
        let separator = "\n" + indent.indentation() + kind.prefix
        return kind.prefix + self.text.joined(separator: separator)
      }
    case .block, .docBlock:
      let separator = "\n"
      return kind.prefix + self.text.joined(separator: separator) + "*/"
    }
  }

  mutating func addText(_ text: [String]) {
    for line in text {
      self.text.append(line)
      self.length += line.count + self.kind.prefixLength + 1
    }
  }
}
