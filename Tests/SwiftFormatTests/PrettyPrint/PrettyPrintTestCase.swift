import SwiftFormat
import SwiftOperators
import SwiftSyntax
import SwiftParser
import XCTest

@_spi(Rules) @_spi(Testing) import SwiftFormat
@_spi(Testing) import _SwiftFormatTestSupport

class PrettyPrintTestCase: DiagnosingTestCase {
  /// Asserts that the input string, when pretty printed, is equal to the expected string.
  ///
  /// - Parameters:
  ///   - input: The input text to pretty print.
  ///   - expected: The expected pretty-printed output.
  ///   - linelength: The maximum allowed line length of the output.
  ///   - configuration: The formatter configuration.
  ///   - whitespaceOnly: If true, the pretty printer should only apply whitespace changes and omit
  ///     changes that insert or remove non-whitespace characters (like trailing commas).
  ///   - findings: A list of `FindingSpec` values that describe the findings that are expected to
  ///     be emitted. These are currently only checked if `whitespaceOnly` is true.
  ///   - file: The file in which failure occurred. Defaults to the file name of the test case in
  ///     which this function was called.
  ///   - line: The line number on which failure occurred. Defaults to the line number on which this
  ///     function was called.
  final func assertPrettyPrintEqual(
    input: String,
    expected: String,
    linelength: Int,
    configuration: Configuration = Configuration.forTesting,
    whitespaceOnly: Bool = false,
    findings: [FindingSpec] = [],
    file: StaticString = #file,
    line: UInt = #line
  ) {
    var configuration = configuration
    configuration.lineLength = linelength

    let markedInput = MarkedText(textWithMarkers: input)
    var emittedFindings = [Finding]()

    // Assert that the input, when formatted, is what we expected.
    let (formatted, context) = prettyPrintedSource(
      markedInput.textWithoutMarkers,
      configuration: configuration,
      selection: markedInput.selection,
      whitespaceOnly: whitespaceOnly,
      findingConsumer: { emittedFindings.append($0) })
    assertStringsEqualWithDiff(
      formatted, expected,
      "Pretty-printed result was not what was expected",
      file: file, line: line)

    // FIXME: It would be nice to check findings when whitespaceOnly == false, but their locations
    // are wrong.
    if whitespaceOnly {
      assertFindings(
        expected: findings,
        markerLocations: markedInput.markers,
        emittedFindings: emittedFindings,
        context: context,
        file: file,
        line: line)
    }

    // Idempotency check: Running the formatter multiple times should not change the outcome.
    // Assert that running the formatter again on the previous result keeps it the same.
    let (reformatted, _) = prettyPrintedSource(
      formatted,
      configuration: configuration,
      selection: markedInput.selection,
      whitespaceOnly: whitespaceOnly,
      findingConsumer: { _ in }  // Ignore findings during the idempotence check.
    )
    assertStringsEqualWithDiff(
      reformatted, formatted, "Pretty printer is not idempotent", file: file, line: line)
  }

  /// Returns the given source code reformatted with the pretty printer.
  ///
  /// - Parameters:
  ///   - source: The source text to pretty print.
  ///   - configuration: The formatter configuration.
  ///   - whitespaceOnly: If true, the pretty printer should only apply whitespace changes and omit
  ///     changes that insert or remove non-whitespace characters (like trailing commas).
  ///   - findingConsumer: A function called for each finding that is emitted by the pretty printer.
  /// - Returns: The pretty-printed text, or nil if an error occurred and a test failure was logged.
  private func prettyPrintedSource(
    _ source: String,
    configuration: Configuration,
    selection: Selection?,
    whitespaceOnly: Bool,
    findingConsumer: @escaping (Finding) -> Void
  ) -> (String, Context) {
    // Ignore folding errors for unrecognized operators so that we fallback to a reasonable default.
    let sourceFileSyntax =
      OperatorTable.standardOperators.foldAll(Parser.parse(source: source)) { _ in }
        .as(SourceFileSyntax.self)!
    let context = makeContext(
      sourceFileSyntax: sourceFileSyntax,
      configuration: configuration,
      selection: selection,
      findingConsumer: findingConsumer)
    let printer = PrettyPrinter(
      context: context,
      source: source,
      node: Syntax(sourceFileSyntax),
      printTokenStream: false,
      whitespaceOnly: whitespaceOnly)
    return (printer.prettyPrint(), context)
  }
}
