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
import Foundation

/// PrettyPrinter takes a Syntax node and outputs a well-formatted, re-indented reproduction of the
/// code as a String.
@_spi(Testing)
public class PrettyPrinter {

  /// Information about an open break that has not yet been closed during the printing stage.
  private struct ActiveOpenBreak {
    /// The index of the open break.
    let index: Int

    /// The kind of open break that created this scope.
    let kind: OpenBreakKind

    /// The line number where the open break occurred.
    let lineNumber: Int

    /// Indicates whether the open break contributed a continuation indent to its scope.
    ///
    /// This indent is applied independently of `contributesBlockIndent`, which means a given break
    /// may apply both a continuation indent and a block indent, either indent, or neither indent.
    var contributesContinuationIndent: Bool

    /// Indicates whether the open break contributed a block indent to its scope. Only one block
    /// indent is applied per line that contains open breaks.
    ///
    /// This indent is applied independently of `contributesContinuationIndent`, which means a given
    /// break may apply both a continuation indent and a block indent, either indent, or neither
    /// indent.
    var contributesBlockIndent: Bool
  }

  /// Records state of `contextualBreakingStart` tokens.
  private struct ActiveBreakingContext {
    /// The line number in the `outputBuffer` where a start token appeared.
    let lineNumber: Int

    enum BreakingBehavior {
      /// The behavior hasn't been determined. This is treated as `continuation`.
      case unset
      /// The break is created as a `continuation` break, setting `currentLineIsContinuation` when
      /// it fires.
      case continuation
      /// The break maintains the existing value of `currentLineIsContinuation` when it fires.
      case maintain
    }

    /// The behavior to use when a `contextual` break fires inside of this break context.
    var contextualBreakingBehavior = BreakingBehavior.unset
  }

  private let context: Context
  private var configuration: Configuration { return context.configuration }
  private let maxLineLength: Int
  private var tokens: [Token]
  private var source: String

  /// Keep track of where formatting was disabled in the original source
  ///
  /// To format a selection, we insert `enableFormatting`/`disableFormatting` tokens into the
  /// stream when entering/exiting a selection range. Those tokens include utf8 offsets into the
  /// original source. When enabling formatting, we copy the text between `disabledPosition` and the
  /// current position to `outputBuffer`. From then on, we continue to format until the next
  /// `disableFormatting` token.
  private var disabledPosition: AbsolutePosition? = nil

  private var outputBuffer: String = ""

  /// The number of spaces remaining on the current line.
  private var spaceRemaining: Int

  /// Keep track of the token lengths.
  private var lengths = [Int]()

  /// Did the previous token create a new line? This is used to determine if a group needs to
  /// consistently break.
  private var lastBreak = false

  /// Keep track of whether we are forcing breaks within a group (for consistent breaking).
  private var forceBreakStack = [false]

  /// If true, the token stream is printed to the console for debugging purposes.
  private var printTokenStream: Bool

  /// Whether the pretty printer should restrict its changes to whitespace. When true, only
  /// whitespace (e.g. spaces, newlines) are modified. Otherwise, text changes (e.g. add/remove
  /// trailing commas) are performed in addition to whitespace.
  private let whitespaceOnly: Bool

  /// Keeps track of the line numbers and indentation states of the open (and unclosed) breaks seen
  /// so far.
  private var activeOpenBreaks: [ActiveOpenBreak] = []

  /// Stack of the active breaking contexts.
  private var activeBreakingContexts: [ActiveBreakingContext] = []

  /// The most recently ended breaking context, used to force certain following `contextual` breaks.
  private var lastEndedBreakingContext: ActiveBreakingContext? = nil

  /// Keeps track of the current line number being printed.
  private var lineNumber: Int = 1

  /// Indicates whether or not the current line being printed is a continuation line.
  private var currentLineIsContinuation = false

  /// Keeps track of the continuation line state as you go into and out of open-close break groups.
  private var continuationStack: [Bool] = []

  /// Keeps track of the line number where comma regions started. Line numbers are removed as their
  /// corresponding end token are encountered.
  private var commaDelimitedRegionStack: [Int] = []

  /// Keeps track of the most recent number of consecutive newlines that have been printed.
  ///
  /// This value is reset to zero whenever non-newline content is printed.
  private var consecutiveNewlineCount = 0

  /// Keeps track of the most recent number of spaces that should be printed before the next text
  /// token.
  private var pendingSpaces = 0

  /// Indicates whether or not the printer is currently at the beginning of a line.
  private var isAtStartOfLine = true

  /// Tracks how many printer control tokens to suppress firing breaks are active.
  private var activeBreakSuppressionCount = 0

  /// Whether breaks are supressed from firing. When true, no breaks should fire and the only way to
  /// move to a new line is an explicit new line token. Discretionary breaks aren't suppressed
  /// if ``allowSuppressedDiscretionaryBreaks`` is true.
  private var isBreakingSuppressed: Bool {
    return activeBreakSuppressionCount > 0
  }

  /// Indicates whether discretionary breaks should still be included even if break suppression is
  /// enabled (see ``isBreakingSuppressed``).
  private var allowSuppressedDiscretionaryBreaks = false

  /// The computed indentation level, as a number of spaces, based on the state of any unclosed
  /// delimiters and whether or not the current line is a continuation line.
  private var currentIndentation: [Indent] {
    let indentation = configuration.indentation
    var totalIndentation: [Indent] = activeOpenBreaks.flatMap { (open) -> [Indent] in
      let count = (open.contributesBlockIndent ? 1 : 0)
        + (open.contributesContinuationIndent ? 1 : 0)
      return Array(repeating: indentation, count: count)
    }
    if currentLineIsContinuation {
      totalIndentation.append(configuration.indentation)
    }
    return totalIndentation
  }

  /// The current line number being printed, with adjustments made for open/close break
  /// calculations.
  ///
  /// Some of the open/close break logic is based on whether matching breaks are located on the same
  /// physical line. In some situations, newlines can be printed before breaks that would cause the
  /// line number to increase by one by the time we reach the break, when we really wish to consider
  /// the break as being located at the end of the previous line.
  private var openCloseBreakCompensatingLineNumber: Int {
    return isAtStartOfLine ? lineNumber - 1 : lineNumber
  }

  /// Creates a new PrettyPrinter with the provided formatting configuration.
  ///
  /// - Parameters:
  ///   - context: The formatter context.
  ///   - node: The node to be pretty printed.
  ///   - printTokenStream: Indicates whether debug information about the token stream should be
  ///     printed to standard output.
  ///   - whitespaceOnly: Whether only whitespace changes should be made.
  public init(context: Context, source: String, node: Syntax, printTokenStream: Bool, whitespaceOnly: Bool) {
    self.context = context
    self.source = source
    let configuration = context.configuration
    self.tokens = node.makeTokenStream(
      configuration: configuration,
      selection: context.selection,
      operatorTable: context.operatorTable)
    self.maxLineLength = configuration.lineLength
    self.spaceRemaining = self.maxLineLength
    self.printTokenStream = printTokenStream
    self.whitespaceOnly = whitespaceOnly
  }

  /// Append the given string to the output buffer.
  ///
  /// No further processing is performed on the string.
  private func writeRaw<S: StringProtocol>(_ str: S) {
    if disabledPosition == nil {
      outputBuffer.append(String(str))
    }
  }

  /// Writes newlines into the output stream, taking into account any preexisting consecutive
  /// newlines and the maximum allowed number of blank lines.
  ///
  /// This function does some implicit collapsing of consecutive newlines to ensure that the
  /// results are consistent when breaks and explicit newlines coincide. For example, imagine a
  /// break token that fires (thus creating a single non-discretionary newline) because it is
  /// followed by a group that contains 2 discretionary newlines that were found in the user's
  /// source code at that location. In that case, the break "overlaps" with the discretionary
  /// newlines and it will write a newline before we get to the discretionaries. Thus, we have to
  /// subtract the previously written newlines during the second call so that we end up with the
  /// correct number overall.
  ///
  /// - Parameter newlines: The number and type of newlines to write.
  private func writeNewlines(_ newlines: NewlineBehavior) {
    let numberToPrint: Int
    switch newlines {
    case .elective:
      numberToPrint = consecutiveNewlineCount == 0 ? 1 : 0
    case .soft(let count, _):
      // We add 1 to the max blank lines because it takes 2 newlines to create the first blank line.
      numberToPrint = min(count, configuration.maximumBlankLines + 1) - consecutiveNewlineCount
    case .hard(let count):
      numberToPrint = count
    }

    guard numberToPrint > 0 else { return }
    writeRaw(String(repeating: "\n", count: numberToPrint))
    lineNumber += numberToPrint
    isAtStartOfLine = true
    consecutiveNewlineCount += numberToPrint
    pendingSpaces = 0
  }

  /// Request that the given number of spaces be printed out before the next text token.
  ///
  /// Spaces are printed only when the next text token is printed in order to prevent us from
  /// printing lines that are only whitespace or have trailing whitespace.
  private func enqueueSpaces(_ count: Int) {
    pendingSpaces += count
    spaceRemaining -= count
  }

  /// Writes the given text to the output stream.
  ///
  /// Before printing the text, this function will print any line-leading indentation or interior
  /// leading spaces that are required before the text itself.
  private func write(_ text: String) {
    if isAtStartOfLine {
      writeRaw(currentIndentation.indentation())
      spaceRemaining = maxLineLength - currentIndentation.length(in: configuration)
      isAtStartOfLine = false
    } else if pendingSpaces > 0  {
      writeRaw(String(repeating: " ", count: pendingSpaces))
    }
    writeRaw(text)
    consecutiveNewlineCount = 0
    pendingSpaces = 0
  }

  /// Print out the provided token, and apply line-wrapping and indentation as needed.
  ///
  /// This method takes a Token and it's length, and it keeps track of how much space is left on the
  /// current line it is printing on. If a token exceeds the remaining space, we break to a new line,
  /// and apply the appropriate level of indentation.
  ///
  /// - Parameters:
  ///   - idx: The index of the token/length pair to be printed.
  private func printToken(idx: Int) {
    let token = tokens[idx]
    let length = lengths[idx]

    if self.printTokenStream {
      printDebugToken(token: token, length: length, idx: idx)
    }
    assert(length >= 0, "Token lengths must be positive")

    switch token {
    case .contextualBreakingStart:
      activeBreakingContexts.append(ActiveBreakingContext(lineNumber: lineNumber))

      // Discard the last finished breaking context to keep it from effecting breaks inside of the
      // new context. The discarded context has already either had an impact on the contextual break
      // after it or there was no relevant contextual break, so it's safe to discard.
      lastEndedBreakingContext = nil

    case .contextualBreakingEnd:
      guard let closedContext = activeBreakingContexts.popLast() else {
        fatalError("Encountered unmatched contextualBreakingEnd token.")
      }

      // Break contexts create scopes, and a breaking context should never be carried between
      // scopes. When there's no active break context, discard the popped one to prevent carrying it
      // into a new scope.
      lastEndedBreakingContext = activeBreakingContexts.isEmpty ? nil : closedContext

    // Check if we need to force breaks in this group, and calculate the indentation to be used in
    // the group.
    case .open(let breaktype):
      // Determine if the break tokens in this group need to be forced.
      if (length > spaceRemaining || lastBreak), case .consistent = breaktype {
        forceBreakStack.append(true)
      } else {
        forceBreakStack.append(false)
      }

    case .close:
      forceBreakStack.removeLast()

    // Create a line break if needed. Calculate the indentation required and adjust spaceRemaining
    // accordingly.
    case .break(let kind, let size, let newline):
      var mustBreak = forceBreakStack.last ?? false

      // Tracks whether the current line should be considered a continuation line, *if and only if
      // the break fires* (note that this is assigned to `currentLineIsContinuation` only in that
      // case).
      var isContinuationIfBreakFires = false

      switch kind {
      case .open(let openKind):
        let lastOpenBreak = activeOpenBreaks.last
        let currentLineNumber = openCloseBreakCompensatingLineNumber

        // Only increase the indentation if there wasn't an open break already encountered on this
        // line (i.e., the previous open break didn't fire), to prevent the indentation of the next
        // line from being more than one level deeper than this line.
        let lastOpenBreakWasSameLine = currentLineNumber == (lastOpenBreak?.lineNumber ?? 0)
        if lastOpenBreakWasSameLine && openKind == .block {
          // If the last open break was on the same line, then we mark it as *not* contributing to
          // the indentation of the subsequent lines. When the breaks are closed, this ensures that
          // indentation is popped evenly (and also popped in an order that causes everything to
          // line up properly).
          activeOpenBreaks[activeOpenBreaks.count - 1].contributesBlockIndent = false
        }

        // If an open break occurs on a continuation line, we must push that continuation
        // indentation onto the stack. The open break will reset the continuation state for the
        // lines within it (unless they are themselves continuations within that particular
        // scope), so we need the continuation indentation to persist across all the lines in that
        // scope. Additionally, continuation open breaks must indent when the break fires.
        let continuationBreakWillFire = openKind == .continuation
          && (isAtStartOfLine || length > spaceRemaining || mustBreak)
        let contributesContinuationIndent = currentLineIsContinuation || continuationBreakWillFire

        activeOpenBreaks.append(
          ActiveOpenBreak(
            index: idx,
            kind: openKind,
            lineNumber: currentLineNumber,
            contributesContinuationIndent: contributesContinuationIndent,
            contributesBlockIndent: openKind == .block))

        continuationStack.append(currentLineIsContinuation)

        // Once we've reached an open break and preserved the continuation state, the "scope" we now
        // enter is *not* a continuation scope. If it was one, we'll re-enter it when we reach the
        // corresponding close.
        currentLineIsContinuation = false

      case .close(let closeMustBreak):
        guard let matchingOpenBreak = activeOpenBreaks.popLast() else {
          fatalError("Unmatched closing break")
        }

        let openedOnDifferentLine
          = openCloseBreakCompensatingLineNumber != matchingOpenBreak.lineNumber

        if matchingOpenBreak.contributesBlockIndent {
          // The actual line number is used, instead of the compensating line number. When the close
          // break is at the start of a new line, the block indentation isn't carried to the new line.
          let currentLine = lineNumber
          // When two or more open breaks are encountered on the same line, only the final open
          // break is allowed to increase the block indent, avoiding multiple block indents. As the
          // open breaks on that line are closed, the new final open break must be enabled again to
          // add a block indent.
          if matchingOpenBreak.lineNumber == currentLine,
            let lastActiveOpenBreak = activeOpenBreaks.last,
            lastActiveOpenBreak.kind == .block,
            !lastActiveOpenBreak.contributesBlockIndent
          {
            activeOpenBreaks[activeOpenBreaks.count - 1].contributesBlockIndent = true
          }
        }

        if closeMustBreak {
          // If it's a mandatory breaking close, then we must break (regardless of line length) if
          // the break is on a different line than its corresponding open break.
          mustBreak = openedOnDifferentLine
        } else if spaceRemaining == 0 {
          // If there is no room left on the line, then we must force this break to fire so that the
          // next token that comes along (typically a closing bracket of some kind) ends up on the
          // next line.
          mustBreak = true
        } else {
          // Otherwise, if we're not force-breaking and we're on a different line than the
          // corresponding open, then the current line must effectively become a continuation line.
          // This ensures that any reset breaks that might follow on the same line are honored. For
          // example, the reset break before the open curly brace below must be made to fire so that
          // the brace can distinguish the argument lines from the block body.
          //
          //    if let someLongVariableName = someLongFunctionName(
          //      firstArgument: argumentValue)
          //    {
          //      ...
          //    }
          //
          // In this case, the preferred style would be to break before the parenthesis and place it
          // on the same line as the curly brace, but that requires quite a bit more contextual
          // information than is easily available. The user can, however, do so with discretionary
          // breaks (if they are enabled).
          //
          // Note that in this case, the transformation of the current line into a continuation line
          // must happen regardless of whether this break fires.
          //
          // Likewise, we need to do this if we popped an old continuation state off the stack,
          // even if the break *doesn't* fire.
          let matchingOpenBreakIndented = matchingOpenBreak.contributesContinuationIndent
            || matchingOpenBreak.contributesBlockIndent
          currentLineIsContinuation = matchingOpenBreakIndented && openedOnDifferentLine
        }

        let wasContinuationWhenOpened = (continuationStack.popLast() ?? false)
          || matchingOpenBreak.contributesContinuationIndent
          // This ensures a continuation indent is propagated to following scope when an initial
          // scope would've indented if the leading break wasn't at the start of a line.
          || (matchingOpenBreak.kind == .continuation && openedOnDifferentLine)

        // Restore the continuation state of the scope we were in before the open break occurred.
        currentLineIsContinuation = currentLineIsContinuation || wasContinuationWhenOpened
        isContinuationIfBreakFires = wasContinuationWhenOpened

      case .continue:
        isContinuationIfBreakFires = true

      case .same:
        break

      case .reset:
        mustBreak = currentLineIsContinuation

      case .contextual:
        // When the last context spanned multiple lines, move the next context (in the same parent
        // break context scope) onto its own line. For example, this is used when the previous
        // context includes a multiline trailing closure or multiline function argument list.
        if let lastBreakingContext = lastEndedBreakingContext {
          if configuration.lineBreakAroundMultilineExpressionChainComponents {
            mustBreak = lastBreakingContext.lineNumber != lineNumber
          }
        }

        // Wait for a contextual break to fire and then update the breaking behavior for the rest of
        // the contextual breaks in this scope to match the behavior of the one that fired.
        let willFire = (!isAtStartOfLine && length > spaceRemaining) || mustBreak
        if willFire {
          // Update the active breaking context according to the most recently finished breaking
          // context so all following contextual breaks in this scope to have matching behavior.
          if let closedContext = lastEndedBreakingContext,
            let activeContext = activeBreakingContexts.last,
            case .unset = activeContext.contextualBreakingBehavior
          {
            activeBreakingContexts[activeBreakingContexts.count - 1].contextualBreakingBehavior =
              (closedContext.lineNumber == lineNumber) ? .continuation : .maintain
          }
        }

        if let activeBreakingContext = activeBreakingContexts.last {
          switch activeBreakingContext.contextualBreakingBehavior {
          case .unset, .continuation:
            isContinuationIfBreakFires = true
          case .maintain:
            isContinuationIfBreakFires = currentLineIsContinuation
          }
        }

        lastEndedBreakingContext = nil
      }

      var overrideBreakingSuppressed = false
      switch newline {
      case .elective: break
      case .soft(_, let discretionary):
        // A discretionary newline (i.e. from the source) should create a line break even if the
        // rules for breaking are disabled.
        overrideBreakingSuppressed = discretionary && allowSuppressedDiscretionaryBreaks
        mustBreak = true
      case .hard:
        // A hard newline must always create a line break, regardless of the context.
        overrideBreakingSuppressed = true
        mustBreak = true
      }

      let suppressBreaking = isBreakingSuppressed && !overrideBreakingSuppressed
      if !suppressBreaking && ((!isAtStartOfLine && length > spaceRemaining) || mustBreak) {
        currentLineIsContinuation = isContinuationIfBreakFires
        writeNewlines(newline)
        lastBreak = true
      } else {
        if isAtStartOfLine {
          // Make sure that the continuation status is correct even at the beginning of a line
          // (for example, after a newline token). This is necessary because a discretionary newline
          // might be inserted into the token stream before a continuation break, and the length of
          // that break might not be enough to satisfy the conditions above but we still need to
          // treat the line as a continuation.
          currentLineIsContinuation = isContinuationIfBreakFires
        }
        enqueueSpaces(size)
        lastBreak = false
      }

    // Print out the number of spaces according to the size, and adjust spaceRemaining.
    case .space(let size, _):
      enqueueSpaces(size)

    // Print any indentation required, followed by the text content of the syntax token.
    case .syntax(let text):
      guard !text.isEmpty else { break }
      lastBreak = false
      write(text)
      spaceRemaining -= text.count

    case .comment(let comment, let wasEndOfLine):
      lastBreak = false

      write(comment.print(
        indent: currentIndentation, width: configuration.lineLength, textWidth: configuration.maximumCommentTextWidth, wrap: configuration.wrapComments))
      if wasEndOfLine {
        if comment.length > spaceRemaining && !isBreakingSuppressed {
          diagnose(.moveEndOfLineComment, category: .endOfLineComment)
        }
      } else {
        spaceRemaining -= comment.length
      }

    case .verbatim(let verbatim):
      writeRaw(verbatim.print(indent: currentIndentation))
      consecutiveNewlineCount = 0
      pendingSpaces = 0
      lastBreak = false
      spaceRemaining -= length

    case .printerControl(let kind):
      switch kind {
      case .disableBreaking(let allowDiscretionary):
        activeBreakSuppressionCount += 1
        // Override the supression of discretionary breaks if we're at the top level or
        // discretionary breaks are currently allowed (false should override true, but not the other
        // way around).
        if activeBreakSuppressionCount == 1 || allowSuppressedDiscretionaryBreaks {
          allowSuppressedDiscretionaryBreaks = allowDiscretionary
        }
      case .enableBreaking:
        activeBreakSuppressionCount -= 1
      }

    case .commaDelimitedRegionStart:
      commaDelimitedRegionStack.append(openCloseBreakCompensatingLineNumber)

    case .commaDelimitedRegionEnd(let hasTrailingComma, let isSingleElement):
      guard let startLineNumber = commaDelimitedRegionStack.popLast() else {
        fatalError("Found trailing comma end with no corresponding start.")
      }

      // We need to specifically disable trailing commas on elements of single item collections.
      // The syntax library can't distinguish a collection's initializer (where the elements are
      // types) from a literal (where the elements are the contents of a collection instance).
      // We never want to add a trailing comma in an initializer so we disable trailing commas on
      // single element collections.
      let shouldHaveTrailingComma =
        startLineNumber != openCloseBreakCompensatingLineNumber && !isSingleElement && configuration.multiElementCollectionTrailingCommas
      if shouldHaveTrailingComma && !hasTrailingComma {
        diagnose(.addTrailingComma, category: .trailingComma)
      } else if !shouldHaveTrailingComma && hasTrailingComma {
        diagnose(.removeTrailingComma, category: .trailingComma)
      }

      let shouldWriteComma = whitespaceOnly ? hasTrailingComma : shouldHaveTrailingComma
      if shouldWriteComma {
        write(",")
        spaceRemaining -= 1
      }

    case .enableFormatting(let enabledPosition):
      guard let disabledPosition else {
        // if we're not disabled, we ignore the token
        break
      }
      let start = source.utf8.index(source.utf8.startIndex, offsetBy: disabledPosition.utf8Offset)
      let end: String.Index
      if let enabledPosition {
        end = source.utf8.index(source.utf8.startIndex, offsetBy: enabledPosition.utf8Offset)
      } else {
        end = source.endIndex
      }
      var text = String(source[start..<end])
      // strip trailing whitespace so that the next formatting can add the right amount
      if let nonWhitespace = text.rangeOfCharacter(
        from: CharacterSet.whitespaces.inverted, options: .backwards) {
        text = String(text[..<nonWhitespace.upperBound])
      }

      self.disabledPosition = nil
      writeRaw(text)
      if text.hasSuffix("\n") {
        isAtStartOfLine = true
        consecutiveNewlineCount = 1
      } else {
        isAtStartOfLine = false
        consecutiveNewlineCount = 0
      }

    case .disableFormatting(let newPosition):
      assert(disabledPosition == nil)
      disabledPosition = newPosition
    }
  }

  /// Scan over the array of Tokens and calculate their lengths.
  ///
  /// This method is based on the `scan` function described in Derek Oppen's "Pretty Printing" paper
  /// (1979).
  ///
  /// - Returns: A String containing the formatted source code.
  public func prettyPrint() -> String {
    // Keep track of the indices of the .open and .break token locations.
    var delimIndexStack = [Int]()
    // Keep a running total of the token lengths.
    var total = 0

    // Calculate token lengths
    for (i, token) in tokens.enumerated() {
      switch token {
      case .contextualBreakingStart:
        lengths.append(0)

      case .contextualBreakingEnd:
        lengths.append(0)

      // Open tokens have lengths equal to the total of the contents of its group. The value is
      // calculated when close tokens are encountered.
      case .open:
        lengths.append(-total)
        delimIndexStack.append(i)

      // Close tokens have a length of 0. Calculate the length of the corresponding open token, and
      // the previous break token (if any).
      case .close:
        lengths.append(0)

        // TODO(dabelknap): Handle the unwrapping more gracefully
        guard let index = delimIndexStack.popLast() else {
          print("Bad index 1")
          return ""
        }
        lengths[index] += total

        // TODO(dabelknap): Handle the unwrapping more gracefully
        if case .break = tokens[index] {
          guard let index = delimIndexStack.popLast() else {
            print("Bad index 2")
            return ""
          }
          lengths[index] += total
        }

      // Break lengths are equal to its size plus the token or group following it. Calculate the
      // length of any prior break tokens.
      case .break(_, let size, let newline):
        if let index = delimIndexStack.last, case .break = tokens[index] {
          lengths[index] += total
          delimIndexStack.removeLast()
        }
        lengths.append(-total)
        delimIndexStack.append(i)

        if case .elective = newline {
          total += size
        } else {
          // `size` is never used in this case, because the break always fires. Use `maxLineLength`
          // to ensure enclosing groups are large enough to force preceding breaks to fire.
          total += maxLineLength
        }

      // Space tokens have a length equal to its size.
      case .space(let size, _):
        lengths.append(size)
        total += size

      // Syntax tokens have a length equal to the number of columns needed to print its contents.
      case .syntax(let text):
        lengths.append(text.count)
        total += text.count

      case .comment(let comment, let wasEndOfLine):
        lengths.append(comment.length)
        total += wasEndOfLine ? 0 : comment.length

      case .verbatim(let verbatim):
        let length = verbatim.prettyPrintingLength(maximum: maxLineLength)
        lengths.append(length)
        total += length

      case .printerControl:
        // Control tokens have no length. They aren't printed.
        lengths.append(0)

      case .commaDelimitedRegionStart:
        lengths.append(0)

      case .commaDelimitedRegionEnd(_, let isSingleElement):
        // The token's length is only necessary when a comma will be printed, but it's impossible to
        // know at this point whether the region-start token will be on the same line as this token.
        // Without adding this length to the total, it would be possible for this comma to be
        // printed in column `maxLineLength`. Unfortunately, this can cause breaks to fire
        // unnecessarily when the enclosed tokens comma would fit within `maxLineLength`.
        let length = isSingleElement ? 0 : 1
        total += length
        lengths.append(length)

      case .enableFormatting, .disableFormatting:
        // no effect on length calculations
        lengths.append(0)
      }
    }

    // There may be an extra break token that needs to have its length calculated.
    assert(delimIndexStack.count < 2, "Too many unresolved delimiter token lengths.")
    if let index = delimIndexStack.popLast() {
      if case .open = tokens[index] {
        assert(false, "Open tokens must be closed.")
      }
      lengths[index] += total
    }

    // Print out the token stream, wrapping according to line-length limitations.
    for i in 0..<tokens.count {
      printToken(idx: i)
    }

    guard activeOpenBreaks.isEmpty else {
      fatalError("At least one .break(.open) was not matched by a .break(.close)")
    }

    return outputBuffer
  }

  /// Used to track the indentation level for the debug token stream output.
  var debugIndent: [Indent] = []

  /// Print out the token stream to the console for debugging.
  ///
  /// Indentation is applied to make identification of groups easier.
  private func printDebugToken(token: Token, length: Int, idx: Int) {
    func printDebugIndent() {
      print(debugIndent.indentation(), terminator: "")
    }

    switch token {
    case .syntax(let syntax):
      printDebugIndent()
      print("[SYNTAX \"\(syntax)\" Length: \(length) Idx: \(idx)]")

    case .break(let kind, let size, let newline):
      printDebugIndent()
      print("[BREAK Kind: \(kind) Size: \(size) Length: \(length) NL: \(newline) Idx: \(idx)]")

    case .open(let breakstyle):
      printDebugIndent()
      switch breakstyle {
      case .consistent:
        print("[OPEN Consistent Length: \(length) Idx: \(idx)]")
      case .inconsistent:
        print("[OPEN Inconsistent Length: \(length) Idx: \(idx)]")
      }
      debugIndent.append(.spaces(2))

    case .close:
      debugIndent.removeLast()
      printDebugIndent()
      print("[CLOSE Idx: \(idx)]")

    case .space(let size, let flexible):
      printDebugIndent()
      print("[SPACE Size: \(size) Flexible: \(flexible) Length: \(length) Idx: \(idx)]")

    case .comment(let comment, let wasEndOfLine):
      printDebugIndent()
      switch comment.kind {
      case .line:
        print("[COMMENT Line Length: \(length) EOL: \(wasEndOfLine) Idx: \(idx)]")
      case .docLine:
        print("[COMMENT DocLine Length: \(length) EOL: \(wasEndOfLine) Idx: \(idx)]")
      case .block:
        print("[COMMENT Block Length: \(length) EOL: \(wasEndOfLine) Idx: \(idx)]")
      case .docBlock:
        print("[COMMENT DocBlock Length: \(length) EOL: \(wasEndOfLine) Idx: \(idx)]")
      }
      printDebugIndent()
      print(comment.print(indent: debugIndent, width: configuration.lineLength, textWidth: configuration.maximumCommentTextWidth,  wrap: false))

    case .verbatim(let verbatim):
      printDebugIndent()
      print("[VERBATIM Length: \(length) Idx: \(idx)]")
      print(verbatim.print(indent: debugIndent))

    case .printerControl(let kind):
      printDebugIndent()
      print("[PRINTER CONTROL Kind: \(kind) Idx: \(idx)]")

    case .commaDelimitedRegionStart:
      printDebugIndent()
      print("[COMMA DELIMITED START Idx: \(idx)]")

    case .commaDelimitedRegionEnd:
      printDebugIndent()
      print("[COMMA DELIMITED END Idx: \(idx)]")

    case .contextualBreakingStart:
      printDebugIndent()
      print("[START BREAKING CONTEXT Idx: \(idx)]")

    case .contextualBreakingEnd:
      printDebugIndent()
      print("[END BREAKING CONTEXT Idx: \(idx)]")

    case .enableFormatting(let pos):
      printDebugIndent()
      print("[ENABLE FORMATTING utf8 offset: \(String(describing: pos))]")

    case .disableFormatting(let pos):
      printDebugIndent()
      print("[DISABLE FORMATTING utf8 offset: \(pos)]")
    }
  }

  /// Emits a finding with the given message and category at the current location in `outputBuffer`.
  private func diagnose(_ message: Finding.Message, category: PrettyPrintFindingCategory) {
    // Add 1 since columns uses 1-based indices.
    let column = maxLineLength - spaceRemaining + 1
    context.findingEmitter.emit(
      message,
      category: category,
      location: Finding.Location(file: context.fileURL.path, line: lineNumber, column: column))
  }
}

extension Finding.Message {
  fileprivate static let moveEndOfLineComment: Finding.Message =
    "move end-of-line comment that exceeds the line length"

  fileprivate static let addTrailingComma: Finding.Message =
    "add trailing comma to the last element in multiline collection literal"

  fileprivate static let removeTrailingComma: Finding.Message =
    "remove trailing comma from the last element in single line collection literal"
}
