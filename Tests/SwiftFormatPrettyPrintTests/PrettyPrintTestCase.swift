import SwiftFormatConfiguration
import SwiftFormatCore
import SwiftSyntax
import XCTest

@testable import SwiftFormatPrettyPrint

public class PrettyPrintTestCase: XCTestCase {

  public func assertPrettyPrintEqual(
    input: String,
    expected: String,
    linelength: Int,
    applicationRangeBuilder: ((SourceFileSyntax) -> SourceRange)? = nil,
    configuration: Configuration = Configuration(),
    file: StaticString = #file,
    line: UInt = #line
  ) {
    configuration.lineLength = linelength

    // Assert that the input, when formatted, is what we expected.
    if let formatted = prettyPrintedSource(input, configuration: configuration, applicationRangeBuilder: applicationRangeBuilder) {
      XCTAssertEqual(
        expected, formatted,
        "Pretty-printed result was not what was expected",
        file: file, line: line)

      // Idempotency check: Running the formatter multiple times should not change the outcome.
      // Assert that running the formatter again on the previous result keeps it the same.
      if let reformatted = prettyPrintedSource(formatted, configuration: configuration, applicationRangeBuilder:
        applicationRangeBuilder) {
        XCTAssertEqual(
          formatted, reformatted, "Pretty printer is not idempotent", file: file, line: line)
      }
    }
  }

  /// Returns the given source code reformatted with the pretty printer.
  private func prettyPrintedSource(_ source: String, configuration: Configuration, applicationRangeBuilder: ((SourceFileSyntax) -> SourceRange)? = nil) -> String?
  {
    let sourceFileSyntax: SourceFileSyntax
    do {
      sourceFileSyntax = try SyntaxParser.parse(source: source)
    } catch {
      XCTFail("Parsing failed with error: \(error)")
      return nil
    }

    let context = Context(
      configuration: configuration,
      diagnosticEngine: nil,
      fileURL: URL(fileURLWithPath: "/tmp/file.swift"),
      sourceFileSyntax: sourceFileSyntax,
      applicationRange: applicationRangeBuilder?(sourceFileSyntax))

    let printer = PrettyPrinter(context: context, node: sourceFileSyntax, printTokenStream: false)
    return printer.prettyPrint()
  }
}
