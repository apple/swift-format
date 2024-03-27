import SwiftFormat
import SwiftSyntax
import SwiftParser
import XCTest

@_spi(Testing) import SwiftFormat
@_spi(Testing) import _SwiftFormatTestSupport

class WhitespaceTestCase: DiagnosingTestCase {
  /// Perform whitespace linting by comparing the input text from the user with the expected
  /// formatted text.
  ///
  /// - Parameters:
  ///   - input: The user's input text.
  ///   - expected: The formatted text.
  ///   - linelength: The maximum allowed line length of the output.
  ///   - findings: A list of `FindingSpec` values that describe the findings that are expected to
  ///     be emitted.
  ///   - file: The file the test resides in (defaults to the current caller's file).
  ///   - line: The line the test resides in (defaults to the current caller's line).
  final func assertWhitespaceLint(
    input: String,
    expected: String,
    linelength: Int? = nil,
    findings: [FindingSpec],
    file: StaticString = #file,
    line: UInt = #line
  ) {
    let markedText = MarkedText(textWithMarkers: input)

    let sourceFileSyntax = Parser.parse(source: markedText.textWithoutMarkers)
    var configuration = Configuration.forTesting
    if let linelength = linelength {
      configuration.lineLength = linelength
    }

    var emittedFindings = [Finding]()

    let context = makeContext(
      sourceFileSyntax: sourceFileSyntax,
      configuration: configuration,
      selection: nil,
      findingConsumer: { emittedFindings.append($0) })
    let linter = WhitespaceLinter(
      user: markedText.textWithoutMarkers, formatted: expected, context: context)
    linter.lint()

    assertFindings(
      expected: findings,
      markerLocations: markedText.markers,
      emittedFindings: emittedFindings,
      context: context,
      file: file,
      line: line)
  }
}
