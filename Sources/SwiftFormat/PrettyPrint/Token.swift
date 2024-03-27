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

import SwiftSyntax

enum GroupBreakStyle {
  /// A consistent break indicates that the break will always be finalized as a newline
  /// if wrapping occurs.
  case consistent

  /// Inconsistent breaks will only be expressed as a newline if they're required to be wrapped as
  /// their addition to the line would go past the line length limit.
  case inconsistent
}

enum OpenBreakKind: Equatable {
  /// An open break that applies a block indent to its scope and is allowed to apply a continuation
  /// indent if and only if the line on which the open break occurs is a continuation line.
  case block

  /// An open break that always applies up to one continuation indent to its scope. A continuation
  /// indent is applied if either the line on which this break is encountered is a continuation or
  /// if this break fires. A continuation open break never applies a block indent to its scope.
  case continuation
}

enum BreakKind: Equatable {
  /// If line wrapping occurs at an `open` break, then the base indentation level increases by one
  /// indentation unit until the corresponding `close` break is encountered.
  case open(kind: OpenBreakKind)

  /// If line wrapping occurs at a `close` break, then the base indentation level returns to the
  /// value it had before the corresponding `open` break.
  ///
  /// If `mustBreak` is true, then this break will always produce a line break when it occurs on a
  /// different line than its corresponding `open` break. This is the behavior one typically wants
  /// when laying out curly-brace delimited blocks or array/dictionary literals. If `mustBreak` is
  /// false, then this break will only produce a line break when absolutely necessary (i.e., if the
  /// rest of the line's length required it). This behavior is desirable for the parentheses around
  /// function calls, where there is not typically a need for a line break before the closing
  /// parenthesis.
  ///
  /// In either case above, the base indentation level of subsequent tokens is still adjusted.
  case close(mustBreak: Bool)

  /// If line wrapping occurs at a `continue` break, then the following line will be treated as a
  /// continuation line (indented one unit further than the base level) without changing the base
  /// level.
  ///
  /// An example use of a `continue` break is when an expression is split across multiple lines;
  /// the break before each operator is a continuation:
  ///
  /// ```swift
  /// let someLongVariable = someLongExpression
  ///   + anotherLongExpression - aThirdLongExpression
  ///   + somethingElse
  /// ```
  case `continue`

  /// If line wrapping occurs at a `same` break, then the following line will be indented at the
  /// base indentation level instead of an increased continuation level.
  ///
  /// An example use of a `same` break is to align the first element on each line in a
  /// comma-delimited list:
  ///
  /// ```swift
  /// let array = [
  ///   1, 2, 3,
  ///   4, 5, 6,
  ///   7, 8, 9,
  /// ]
  /// ```
  case same

  /// A `reset` break that occurs on a continuation line forces a line break that ends the
  /// continuation and causes the tokens on the next line to be indented at the base indentation
  /// level.
  ///
  /// These breaks are used, for example, to force an open curly brace onto a new line if it would
  /// otherwise fit on a continuation line, so that the body of the braced block can be
  /// distinguished from the continuation line(s) above it:
  ///
  /// ```swift
  /// func foo(_ x: Int) {
  ///   // This is allowed because the line above is not a continuation.
  /// }
  ///
  /// func foo(
  ///   _ x: Int
  /// ) {
  ///   // This is also allowed, for the same reason.
  /// }
  ///
  /// func foo(_ x: Int)
  ///   throws -> Int
  /// {
  ///   // Here we must force the brace down or the block contents would
  ///   // collide with the "throws" line.
  /// }
  /// ```
  case reset

  /// A `contextual` break acts as either a `continue` break or maintains the existing level of
  /// indentation when it fires. The contextual breaking behavior of a given contextual breaking
  /// scope (i.e. inside a `contextualBreakingStart`/`contextualBreakingEnd` region) is set by the
  /// first child `contextualBreakingStart`/`contextualBreakingEnd` pair. When the first child is
  /// multiline the contextual breaks maintain indentation and they are continuations otherwise.
  ///
  /// These are used when multiple related breaks need to exhibit the same behavior based the
  /// context in which they appear. For example, when breaks exist between expressions that are
  /// chained together (e.g. member access) and indenting the line *after* a closing paren/brace
  /// looks better indented when the previous expr was 1 line but not indented when the expr was
  /// multiline.
  case contextual

  /// A `close` break that defaults to forced breaking behavior.
  static let close = BreakKind.close(mustBreak: true)

  /// An `open` break that defaults to applying a block indent to its scope.
  static let open = BreakKind.open(kind: .block)
}

/// Behaviors for creating newlines as part of a break, i.e. where breaking onto a newline is
/// allowed.
enum NewlineBehavior {
  /// Breaking onto a newline is allowed if necessary, but is not required. `ignoresDiscretionary`
  /// specifies whether a user-entered discretionary newline should be respected.
  case elective(ignoresDiscretionary: Bool)

  /// Breaking onto a newline `count` times is required, unless it would create more blank lines
  /// than are allowed by the current configuration. Any blank lines over the configured limit are
  /// discarded. `discretionary` tracks whether these newlines were created based on user-entered
  /// discretionary newlines, from the source, or were inserted by the formatter.
  case soft(count: Int, discretionary: Bool)

  /// Breaking onto a newline `count` times is required and any limits on blank lines are
  /// **ignored**. Exactly `count` newlines are always printed, regardless of existing consecutive
  /// newlines and the configured maximum number of blank lines.
  case hard(count: Int)

  /// An elective newline that respects discretionary newlines from the user-entered text.
  static let elective = NewlineBehavior.elective(ignoresDiscretionary: false)

  /// A single soft newline that is created by the formatter, i.e. *not* discretionary.
  static let soft = NewlineBehavior.soft(count: 1, discretionary: false)

  /// A single hard newline.
  static let hard = NewlineBehavior.hard(count: 1)
}

/// Kinds of printer control tokens that can be used to customize the pretty printer's behavior in
/// a subsection of a token stream.
enum PrinterControlKind {
  /// A signal that break tokens shouldn't be allowed to fire until a corresponding enable breaking
  /// control token is encountered.
  ///
  /// It's valid to nest `disableBreaking` and `enableBreaking` tokens. Breaks will be suppressed
  /// long as there is at least 1 unmatched disable token. If `allowDiscretionary` is `true`, then
  /// discretionary breaks aren't effected. An `allowDiscretionary` value of true never overrides a
  /// value of false. Hard breaks are always inserted no matter what.
  case disableBreaking(allowDiscretionary: Bool)

  /// A signal that break tokens should be allowed to fire following this token, as long as there
  /// are no other unmatched disable tokens.
  case enableBreaking
}

enum Token {
  case syntax(String)
  case open(GroupBreakStyle)
  case close
  case `break`(BreakKind, size: Int, newlines: NewlineBehavior)
  case space(size: Int, flexible: Bool)
  case comment(Comment, wasEndOfLine: Bool)
  case verbatim(Verbatim)
  case printerControl(kind: PrinterControlKind)

  /// Marks the beginning of a comma delimited collection, where a trailing comma should be inserted
  /// at `commaDelimitedRegionEnd` if and only if the collection spans multiple lines.
  case commaDelimitedRegionStart

  /// Marks the end of a comma delimited collection, where a trailing comma should be inserted
  /// if and only if the collection spans multiple lines and has multiple elements.
  case commaDelimitedRegionEnd(hasTrailingComma: Bool, isSingleElement: Bool)

  /// Starts a scope where `contextual` breaks have consistent behavior.
  case contextualBreakingStart

  /// Ends a scope where `contextual` breaks have consistent behavior.
  case contextualBreakingEnd

  /// Turn formatting back on at the given position in the original file
  /// nil is used to indicate the rest of the file should be output
  case enableFormatting(AbsolutePosition?)

  /// Turn formatting off at the given position in the original file.
  case disableFormatting(AbsolutePosition)

  // Convenience overloads for the enum types
  static let open = Token.open(.inconsistent, 0)

  static func open(_ breakStyle: GroupBreakStyle, _ offset: Int) -> Token {
    return Token.open(breakStyle)
  }

  static let space = Token.space(size: 1, flexible: false)

  static func space(size: Int) -> Token {
    return .space(size: size, flexible: false)
  }

  static let `break` = Token.break(.continue, size: 1, newlines: .elective)

  static func `break`(_ kind: BreakKind, size: Int = 1) -> Token {
    return .break(kind, size: size, newlines: .elective)
  }

  static func `break`(_ kind: BreakKind, newlines: NewlineBehavior) -> Token {
    return .break(kind, size: 1, newlines: newlines)
  }
}
