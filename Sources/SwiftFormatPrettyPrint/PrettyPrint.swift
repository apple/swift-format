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

import SwiftFormatConfiguration
import SwiftFormatCore
import SwiftSyntax

/// PrettyPrinter takes a Syntax node and outputs a well-formatted, re-indented reproduction of the
/// code as a String.
public class PrettyPrinter {

  /// Information about an open break that has not yet been closed during the printing stage.
  private struct ActiveOpenBreak {

    /// The line number where the open break occurred.
    let lineNumber: Int

    /// Indicates whether the open break contributed to an increase in indentation of its "scope".
    ///
    /// An open break does not contribute to indentation if it is followed by another open break on
    /// the same line.
    var didIndent: Bool

    init(lineNumber: Int) {
      self.lineNumber = lineNumber

      // Assume that it will indent initially. This may be flipped later if another open break is
      // later encountered on the same line.
      self.didIndent = true
    }
  }

  private let context: Context
  private var configuration: Configuration { return context.configuration }
  private let maxLineLength: Int
  private var tokens: [Token]
  private var outputBuffer: String = ""

  /// The number of spaces remaining on the current line.
  private var spaceRemaining: Int

  /// Keep track of the token lengths.
  private var lengths = [Int]()

  /// Did the previous token create a new line? This is used to determine if a group needs to
  /// consistently break.
  private var lastBreak = false

  /// Keeps track of the base indentation level (as determined by the unclosed `.break(.open)`
  /// tokens) as a sequence of space or tab values.
  private var indentationStack: [Indent] = []

  /// Keep track of whether we are forcing breaks within a group (for consistent breaking).
  private var forceBreakStack = [false]

  /// If true, the token stream is printed to the console for debugging purposes.
  private var printTokenStream: Bool

  /// Keeps track of the line numbers and indentation states of the open (and unclosed) breaks seen
  /// so far.
  private var activeOpenBreaks: [ActiveOpenBreak] = []

  /// Keeps track of the current line number being printed.
  private var lineNumber: Int = 1

  /// Indicates whether or not the current line being printed is a continuation line.
  private var currentLineIsContinuation = false

  /// Keeps track of the continuation line state as you go into and out of open-close break groups.
  private var continuationStack: [Bool] = []

  /// Keeps track of the most recent number of consecutive newlines that have been printed.
  ///
  /// This value is reset to zero whenever non-newline content is printed.
  private var consecutiveNewlineCount = 0

  /// Keeps track of the most recent number of spaces that should be printed before the next text
  /// token.
  private var pendingSpaces = 0

  /// Indicates whether or not the printer is currently at the beginning of a line.
  private var isAtStartOfLine = true

  /// The kind of the last break token that was printed.
  private var lastBreakKind: BreakKind = .reset

  /// The computed indentation level, as a number of spaces, based on the state of any unclosed
  /// delimiters and whether or not the current line is a continuation line.
  private var currentIndentation: [Indent] {
    var totalIndentation = indentationStack
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

  /// Represent the line in the original code for token at index i
  private var lineForToken: [Int]
  
  /// Creates a new PrettyPrinter with the provided formatting configuration.
  ///
  /// - Parameters:
  ///   - context: The formatter context.
  ///   - node: The node to be pretty printed.
  public init(context: Context, node: Syntax, printTokenStream: Bool) {
    self.context = context
    let configuration = context.configuration
    self.tokens = node.makeTokenStream(configuration: configuration)
    self.maxLineLength = configuration.lineLength
    self.spaceRemaining = self.maxLineLength
    self.printTokenStream = printTokenStream
    self.lineForToken = self.tokens.lineInCode()
  }

  /// Append the given string to the output buffer.
  ///
  /// No further processing is performed on the string.
  private func writeRaw<S: StringProtocol>(_ str: S) {
    outputBuffer.append(String(str))
  }

  /// Ensures that the given number of newlines to the output stream (taking into account any
  /// pre-existing consecutive newlines).
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
  /// - Parameters:
  ///   - count: The number of newlines to write.
  ///   - discretionary: Indicates whether the newlines are user-entered discretionary newlines.
  ///     Discretionary newlines are always printed, after excluding any other consecutive newlines
  ///     thus far, and up through the maximum allowed number provided to the printer at
  ///     initialization time. Non-discretionary newlines are only printed if discretionary newlines
  ///     have already not been printed yet.
  private func writeNewlines(_ count: Int, discretionary: Bool) {
    // We add 1 because it takes 2 newlines to create a blank line.
    let maximumNewlines = configuration.maximumBlankLines + 1
    let numberToPrint: Int
    if count <= maximumNewlines {
      numberToPrint = count - consecutiveNewlineCount
    } else {
      numberToPrint = maximumNewlines - consecutiveNewlineCount
    }

    guard (discretionary && numberToPrint > 0) || consecutiveNewlineCount == 0 else { return }

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
    } else if pendingSpaces > 0 {
      writeRaw(String(repeating: " ", count: pendingSpaces))
    }
    writeRaw(text)
    consecutiveNewlineCount = 0
    pendingSpaces = 0
  }

  private func processTokenAsInOriginalInput(_ token: Token) {
    if case let .syntax(tokenSyntax) = token {
      tokenSyntax.leadingTrivia.write(to: &outputBuffer)
      writeRaw(tokenSyntax.printableText)
      tokenSyntax.trailingTrivia.write(to: &outputBuffer)
    }
  }

  /// Print out the provided token, and apply line-wrapping and indentation as needed.
  ///
  /// This method takes a Token and it's length, and it keeps track of how much space is left on the
  /// current line it is printing on. If a token exceeds the remaning space, we break to a new line,
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

    guard isInProcessingRangeToken(at: idx) else {
      processTokenAsInOriginalInput(token)
      return
    }

    switch token {
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
    case .break(let kind, let size, _):
      lastBreakKind = kind
      var mustBreak = forceBreakStack.last ?? false

      // Tracks whether the current line should be considered a continuation line, *if and only if
      // the break fires* (note that this is assigned to `currentLineIsContinuation` only in that
      // case).
      var isContinuationIfBreakFires = false

      switch kind {
      case .open:
        let lastOpenBreak = activeOpenBreaks.last

        // Only increase the indentation if there wasn't an open break already encountered on this
        // line (i.e., the previous open break didn't fire), to prevent the indentation of the next
        // line from being more than one level deeper than this line.
        let lastOpenBreakWasSameLine
          = openCloseBreakCompensatingLineNumber == (lastOpenBreak?.lineNumber ?? 0)
        if lastOpenBreakWasSameLine {
          // If the last open break was on the same line, then we mark it as *not* contributing to
          // the indentation of the subsequent lines. When the breaks are closed, this ensures that
          // indentation is popped evenly (and also popped in an order that causes everything to
          // line up properly).
          activeOpenBreaks[activeOpenBreaks.count - 1].didIndent = false
        } else {
          // If an open break occurs on a continuation line, we must push that continuation
          // indentation onto the stack. The open break will reset the continuation state for the
          // lines within it (unless they are themselves continuations within that particular
          // scope), so we need the continuation indentation to persist across all the lines in that
          // scope.
          if currentLineIsContinuation {
            indentationStack.append(configuration.indentation)
          }

          indentationStack.append(configuration.indentation)
        }

        continuationStack.append(currentLineIsContinuation)
        activeOpenBreaks.append(ActiveOpenBreak(lineNumber: openCloseBreakCompensatingLineNumber))

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

        if matchingOpenBreak.didIndent {
          // We can remove an indentation unit if the close was on a different line than the
          // matching open, if the open break before that also contributed to indentation, or if
          // there are no more open breaks. Otherwise, we update the previous active open break to
          // indicate that *it* contributed to indentation and move on.
          if matchingOpenBreak.lineNumber != openCloseBreakCompensatingLineNumber
            || activeOpenBreaks.isEmpty || activeOpenBreaks.last?.didIndent == true
          {
            indentationStack.removeLast()
          } else {
            activeOpenBreaks[activeOpenBreaks.count - 1].didIndent = true
          }
        }

        let wasContinuationWhenOpened = continuationStack.popLast() ?? false

        // Un-persist any continuation indentation that may have applied to the open/close scope.
        if wasContinuationWhenOpened {
          indentationStack.removeLast()
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
          currentLineIsContinuation = matchingOpenBreak.didIndent && openedOnDifferentLine
        }

        // Restore the continuation state of the scope we were in before the open break occurred.
        currentLineIsContinuation = currentLineIsContinuation || wasContinuationWhenOpened
        isContinuationIfBreakFires = wasContinuationWhenOpened

      case .continue:
        isContinuationIfBreakFires = true

      case .same:
        break

      case .reset:
        mustBreak = currentLineIsContinuation
      }

      if length > spaceRemaining || mustBreak {
        currentLineIsContinuation = isContinuationIfBreakFires
        writeNewlines(1, discretionary: false)
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

    // Apply `count` line breaks, calculate the indentation required, and adjust spaceRemaining.
    case .newlines(let count, let discretionary):
      currentLineIsContinuation = (lastBreakKind == .continue)
      writeNewlines(count, discretionary: discretionary)
      lastBreak = true

    // Print any indentation required, followed by the text content of the syntax token.
    case .syntax(let tokenSyntax):
      let text = tokenSyntax.printableText
      guard !text.isEmpty else { break }
      lastBreak = false
      write(text)
      spaceRemaining -= text.count

    case .comment(let comment, let wasEndOfLine):
      lastBreak = false

      write(comment.print())
      if wasEndOfLine {
        if comment.length > spaceRemaining {
          diagnose(.moveEndOfLineComment, at: comment.position)
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
    }
  }

  /// Scan over the array of Tokens and calculate their lengths.
  ///
  /// This method is based on the `scan` function described in Derek Oppen's "Pretty Printing" paper
  /// (1979).
  ///
  /// - Returns: A String containing the formatted source code.
  public func prettyPrint() -> String {
    // Keep track of the indicies of the .open and .break token locations.
    var delimIndexStack = [Int]()
    // Keep a running total of the token lengths.
    var total = 0

    // Calculate token lengths
    for (i, token) in tokens.enumerated() {
      switch token {
      // Open tokens have lengths equal to the total of the contents of its group. The value is
      // calcualted when close tokens are encountered.
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
      case .break(_, let size, _):
        if let index = delimIndexStack.last, case .break = tokens[index] {
          lengths[index] += total
          delimIndexStack.removeLast()
        }

        lengths.append(-total)
        delimIndexStack.append(i)
        total += size

      // Space tokens have a length equal to its size.
      case .space(let size, _):
        lengths.append(size)
        total += size

      // The length of newlines are equal to the maximum allowed line length. Calculate the length
      // of any prior break tokens.
      case .newlines:
        if let index = delimIndexStack.last, case .break = tokens[index] {
          lengths[index] += total
          delimIndexStack.removeLast()
        }

        // Since newlines must always cause a line-break, we set their length as the full allowed
        // width of the line. This causes any enclosing groups to have a length exceeding the line
        // limit, and so the group must break and indent. e.g. single-line versus multi-line
        // function bodies.
        lengths.append(maxLineLength)
        total += maxLineLength

      // Syntax tokens have a length equal to the number of columns needed to print its contents.
      case .syntax(let tokenSyntax):
        let text = tokenSyntax.printableText
        lengths.append(text.count)
        total += text.count

      case .comment(let comment, let wasEndOfLine):
        lengths.append(comment.length)
        total += wasEndOfLine ? 0 : comment.length

      case .verbatim(let verbatim):
        var length: Int
        if verbatim.lines.count > 1 {
          length = maxLineLength
        } else if verbatim.lines.count == 0 {
          length = 0
        } else {
          length = verbatim.lines[0].count
        }
        lengths.append(length)
        total += length
      }
    }

    // There may be an extra break token that needs to have its length calculated.
    assert(delimIndexStack.count < 2, "Too many unresolved delmiter token lengths.")
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

//    guard activeOpenBreaks.isEmpty else {
//      fatalError("At least one .break(.open) was not matched by a .break(.close)")
//    }

    return outputBuffer
  }

  private func isInProcessingRangeToken(at idx: Int) -> Bool {
    let line = lineForToken[idx]
    let lo = context.applicationRange?.start.line ?? 2 // lines start from 1, but we subtract 1 later
    let hi = context.applicationRange?.end.line ?? Int.max
    return (lo-1...hi).contains(line)
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

    case .break(let kind, let size, let ignoresDiscretionary):
      printDebugIndent()
      print(
        "[BREAK Kind: \(kind) Size: \(size) Length: \(length) "
          + "Ignores Discretionary NL: \(ignoresDiscretionary) Idx: \(idx)]")

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

    case .newlines(let N, let required):
      printDebugIndent()
      print("[NEWLINES N: \(N) Required: \(required) Length: \(length) Idx: \(idx)]")

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
      print(comment.print())

    case .verbatim(let verbatim):
      printDebugIndent()
      print("[VERBATIM Length: \(length) Idx: \(idx)]")
      print(verbatim.print(indent: debugIndent))
    }
  }

  private func diagnose(_ message: Diagnostic.Message, at position: AbsolutePosition?) {
    let location: SourceLocation?
    if let position = position {
      location = SourceLocation(
        offset: position.utf8Offset, converter: context.sourceLocationConverter)
    } else {
      location = nil
    }
    context.diagnosticEngine?.diagnose(message, location: location)
  }
}

extension Diagnostic.Message {

  static let moveEndOfLineComment = Diagnostic.Message(
    .warning, "End-of-line comment exceeds the line length")
}
