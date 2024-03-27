import SwiftFormat
import SwiftSyntax
import XCTest

@_spi(Rules) @_spi(Testing) import SwiftFormat

/// DiagnosingTestCase is an XCTestCase subclass meant to inject diagnostic-specific testing
/// routines into specific formatting test cases.
open class DiagnosingTestCase: XCTestCase {
  /// Creates and returns a new `Context` from the given syntax tree and configuration.
  ///
  /// The returned context is configured with the given finding consumer to record findings emitted
  /// during the tests, so that they can be asserted later using the `assertFindings` method.
  @_spi(Testing)
  public func makeContext(
    sourceFileSyntax: SourceFileSyntax,
    configuration: Configuration? = nil,
    selection: Selection?,
    findingConsumer: @escaping (Finding) -> Void
  ) -> Context {
    let context = Context(
      configuration: configuration ?? Configuration(),
      operatorTable: .standardOperators,
      findingConsumer: findingConsumer,
      fileURL: URL(fileURLWithPath: "/tmp/test.swift"),
      selection: selection,
      sourceFileSyntax: sourceFileSyntax,
      ruleNameCache: ruleNameCache)
    return context
  }

  /// Asserts that the given list of findings matches a set of specs.
  @_spi(Testing)
  public final func assertFindings(
    expected specs: [FindingSpec],
    markerLocations: [String: Int],
    emittedFindings: [Finding],
    context: Context,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    var emittedFindings = emittedFindings

    // Check for a finding that matches each spec, removing it from the array if found.
    for spec in specs {
      assertAndRemoveFinding(
        findingSpec: spec,
        markerLocations: markerLocations,
        emittedFindings: &emittedFindings,
        context: context,
        file: file,
        line: line)
    }

    // Emit test failures for any findings that did not have matches.
    for finding in emittedFindings {
      let locationString: String
      if let location = finding.location {
        locationString = "line:col \(location.line):\(location.column)"
      } else {
        locationString = "no location provided"
      }
      XCTFail(
        "Unexpected finding '\(finding.message)' was emitted (\(locationString))",
        file: file,
        line: line)
    }
  }

  private func assertAndRemoveFinding(
    findingSpec: FindingSpec,
    markerLocations: [String: Int],
    emittedFindings: inout [Finding],
    context: Context,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    guard let utf8Offset = markerLocations[findingSpec.marker] else {
      XCTFail("Marker '\(findingSpec.marker)' was not found in the input", file: file, line: line)
      return
    }

    let markerLocation =
      context.sourceLocationConverter.location(for: AbsolutePosition(utf8Offset: utf8Offset))

    // Find a finding that has the expected line/column location, ignoring the text.
    // FIXME: We do this to provide a better error message if the finding is in the right place but
    // doesn't have the right message, but this also introduces an order-sensitivity among the
    // specs. Fix this if it becomes an issue.
    let maybeIndex = emittedFindings.firstIndex {
      markerLocation.line == $0.location?.line && markerLocation.column == $0.location?.column
    }
    guard let index = maybeIndex else {
      XCTFail(
        """
        Finding '\(findingSpec.message)' was not emitted at marker '\(findingSpec.marker)' \
        (line:col \(markerLocation.line):\(markerLocation.column), offset \(utf8Offset))
        """,
        file: file,
        line: line)
      return
    }

    // Verify that the finding text also matches what we expect.
    let matchedFinding = emittedFindings.remove(at: index)
    XCTAssertEqual(
      matchedFinding.message.text,
      findingSpec.message,
      """
      Finding emitted at marker '\(findingSpec.marker)' \
      (line:col \(markerLocation.line):\(markerLocation.column), offset \(utf8Offset)) \
      had the wrong message
      """,
      file: file,
      line: line)

    // Assert that a note exists for each of the expected nodes in the finding.
    var emittedNotes = matchedFinding.notes
    for noteSpec in findingSpec.notes {
      assertAndRemoveNote(
        noteSpec: noteSpec,
        markerLocations: markerLocations,
        emittedNotes: &emittedNotes,
        context: context,
        file: file,
        line: line)
    }

    // Emit test failures for any notes that weren't specified.
    for note in emittedNotes {
      let locationString: String
      if let location = note.location {
        locationString = "line:col \(location.line):\(location.column)"
      } else {
        locationString = "no location provided"
      }
      XCTFail(
        "Unexpected note '\(note.message)' was emitted (\(locationString))",
        file: file,
        line: line)
    }
  }

  private func assertAndRemoveNote(
    noteSpec: NoteSpec,
    markerLocations: [String: Int],
    emittedNotes: inout [Finding.Note],
    context: Context,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    guard let utf8Offset = markerLocations[noteSpec.marker] else {
      XCTFail("Marker '\(noteSpec.marker)' was not found in the input", file: file, line: line)
      return
    }

    let markerLocation =
      context.sourceLocationConverter.location(for: AbsolutePosition(utf8Offset: utf8Offset))

    // FIXME: We do this to provide a better error message if the note is in the right place but
    // doesn't have the right message, but this also introduces an order-sensitivity among the
    // specs. Fix this if it becomes an issue.
    let maybeIndex = emittedNotes.firstIndex {
      markerLocation.line == $0.location?.line && markerLocation.column == $0.location?.column
    }
    guard let index = maybeIndex else {
      XCTFail(
        """
        Note '\(noteSpec.message)' was not emitted at marker '\(noteSpec.marker)' \
        (line:col \(markerLocation.line):\(markerLocation.column), offset \(utf8Offset))
        """,
        file: file,
        line: line)
      return
    }

    // Verify that the note text also matches what we expect.
    let matchedNote = emittedNotes.remove(at: index)
    XCTAssertEqual(
      matchedNote.message.text,
      noteSpec.message,
      """
      Note emitted at marker '\(noteSpec.marker)' \
      (line:col \(markerLocation.line):\(markerLocation.column), offset \(utf8Offset)) \
      had the wrong message
      """,
      file: file,
      line: line)
  }

  /// Asserts that the two strings are equal, providing Unix `diff`-style output if they are not.
  ///
  /// - Parameters:
  ///   - actual: The actual string.
  ///   - expected: The expected string.
  ///   - message: An optional description of the failure.
  ///   - file: The file in which failure occurred. Defaults to the file name of the test case in
  ///     which this function was called.
  ///   - line: The line number on which failure occurred. Defaults to the line number on which this
  ///     function was called.
  public final func assertStringsEqualWithDiff(
    _ actual: String,
    _ expected: String,
    _ message: String = "",
    file: StaticString = #file,
    line: UInt = #line
  ) {
    // Use `CollectionDifference` on supported platforms to get `diff`-like line-based output. On
    // older platforms, fall back to simple string comparison.
    if #available(macOS 10.15, *) {
      let actualLines = actual.components(separatedBy: .newlines)
      let expectedLines = expected.components(separatedBy: .newlines)

      let difference = actualLines.difference(from: expectedLines)
      if difference.isEmpty { return }

      var result = ""

      var insertions = [Int: String]()
      var removals = [Int: String]()

      for change in difference {
        switch change {
        case .insert(let offset, let element, _):
          insertions[offset] = element
        case .remove(let offset, let element, _):
          removals[offset] = element
        }
      }

      var expectedLine = 0
      var actualLine = 0

      while expectedLine < expectedLines.count || actualLine < actualLines.count {
        if let removal = removals[expectedLine] {
          result += "-\(removal)\n"
          expectedLine += 1
        } else if let insertion = insertions[actualLine] {
          result += "+\(insertion)\n"
          actualLine += 1
        } else {
          result += " \(expectedLines[expectedLine])\n"
          expectedLine += 1
          actualLine += 1
        }
      }

      let failureMessage = "Actual output (+) differed from expected output (-):\n\(result)"
      let fullMessage = message.isEmpty ? failureMessage : "\(message) - \(failureMessage)"
      XCTFail(fullMessage, file: file, line: line)
    } else {
      // Fall back to simple string comparison on platforms that don't support CollectionDifference.
      let failureMessage = "Actual output differed from expected output:"
      let fullMessage = message.isEmpty ? failureMessage : "\(message) - \(failureMessage)"
      XCTAssertEqual(actual, expected, fullMessage, file: file, line: line)
    }
  }
}
