//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import SwiftDiagnostics
import SwiftOperators
import SwiftSyntax

/// Formats Swift source code or syntax trees according to the Swift style guidelines.
public final class SwiftFormatter {

  /// The configuration settings that control the formatter's behavior.
  public let configuration: Configuration

  /// the ranges of text to format
  public var selection: Selection? = nil

  /// An optional callback that will be notified with any findings encountered during formatting.
  public let findingConsumer: ((Finding) -> Void)?

  /// Advanced options that are useful when debugging the formatter's behavior but are not meant for
  /// general use.
  public var debugOptions: DebugOptions = []

  /// Creates a new Swift code formatter with the given configuration.
  ///
  /// - Parameters:
  ///   - configuration: The configuration settings that control the formatter's behavior.
  ///   - findingConsumer: An optional callback that will be notified with any findings encountered
  ///     during formatting. Unlike the `Linter` API, this defaults to nil for formatting because
  ///     findings are typically less useful than the final formatted output.
  public init(configuration: Configuration, findingConsumer: ((Finding) -> Void)? = nil) {
    self.configuration = configuration
    self.findingConsumer = findingConsumer
  }

  /// Formats the Swift code at the given file URL and writes the result to an output stream.
  ///
  /// This form of the `format` function automatically folds expressions using the default operator
  /// set defined in Swift. If you need more control over this—for example, to provide the correct
  /// precedence relationships for custom operators—you must parse and fold the syntax tree
  /// manually and then call ``format(syntax:assumingFileURL:to:)``.
  ///
  /// - Parameters:
  ///   - url: The URL of the file containing the code to format.
  ///   - outputStream: A value conforming to `TextOutputStream` to which the formatted output will
  ///     be written.
  ///   - parsingDiagnosticHandler: An optional callback that will be notified if there are any
  ///     errors when parsing the source code.
  /// - Throws: If an unrecoverable error occurs when formatting the code.
  public func format<Output: TextOutputStream>(
    contentsOf url: URL,
    to outputStream: inout Output,
    parsingDiagnosticHandler: ((Diagnostic, SourceLocation) -> Void)? = nil
  ) throws {
    guard FileManager.default.isReadableFile(atPath: url.path) else {
      throw SwiftFormatError.fileNotReadable
    }
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
      throw SwiftFormatError.isDirectory
    }

    try format(
      source: String(contentsOf: url, encoding: .utf8),
      assumingFileURL: url,
      selection: nil,
      to: &outputStream,
      parsingDiagnosticHandler: parsingDiagnosticHandler)
  }

  /// Formats the given Swift source code and writes the result to an output stream.
  ///
  /// This form of the `format` function automatically folds expressions using the default operator
  /// set defined in Swift. If you need more control over this—for example, to provide the correct
  /// precedence relationships for custom operators—you must parse and fold the syntax tree
  /// manually and then call ``format(syntax:assumingFileURL:to:)``.
  ///
  /// - Parameters:
  ///   - source: The Swift source code to be formatted.
  ///   - url: A file URL denoting the filename/path that should be assumed for this syntax tree,
  ///     which is associated with any diagnostics emitted during formatting. If this is nil, a
  ///     dummy value will be used.
  ///   - selection: The ranges to format
  ///   - outputStream: A value conforming to `TextOutputStream` to which the formatted output will
  ///     be written.
  ///   - parsingDiagnosticHandler: An optional callback that will be notified if there are any
  ///     errors when parsing the source code.
  /// - Throws: If an unrecoverable error occurs when formatting the code.
  public func format<Output: TextOutputStream>(
    source: String,
    assumingFileURL url: URL?,
    selection: Selection?,
    to outputStream: inout Output,
    parsingDiagnosticHandler: ((Diagnostic, SourceLocation) -> Void)? = nil
  ) throws {
    // If the file or input string is completely empty, do nothing. This prevents even a trailing
    // newline from being emitted for an empty file. (This is consistent with clang-format, which
    // also does not touch an empty file even if the setting to add trailing newlines is enabled.)
    guard !source.isEmpty else { return }

    let sourceFile = try parseAndEmitDiagnostics(
      source: source,
      operatorTable: .standardOperators,
      assumingFileURL: url,
      parsingDiagnosticHandler: parsingDiagnosticHandler)
    try format(
      syntax: sourceFile, source: source, operatorTable: .standardOperators, assumingFileURL: url,
      selection: selection, to: &outputStream)
  }

  /// Formats the given Swift syntax tree and writes the result to an output stream.
  ///
  /// This form of the `format` function does not perform any additional processing on the given
  /// syntax tree. The tree **must** have all expressions folded using an `OperatorTable`, and no
  /// detection of warnings/errors is performed.
  ///
  /// - Note: The formatter may be faster using the source text, if it's available.
  ///
  /// - Parameters:
  ///   - syntax: The Swift syntax tree to be converted to source code and formatted.
  ///   - source: The original Swift source code used to build the syntax tree.
  ///   - operatorTable: The table that defines the operators and their precedence relationships.
  ///     This must be the same operator table that was used to fold the expressions in the `syntax`
  ///     argument.
  ///   - url: A file URL denoting the filename/path that should be assumed for this syntax tree,
  ///     which is associated with any diagnostics emitted during formatting. If this is nil, a
  ///     dummy value will be used.
  ///   - selection: The ranges to format
  ///   - outputStream: A value conforming to `TextOutputStream` to which the formatted output will
  ///     be written.
  /// - Throws: If an unrecoverable error occurs when formatting the code.
  public func format<Output: TextOutputStream>(
    syntax: SourceFileSyntax, source: String, operatorTable: OperatorTable,
    assumingFileURL url: URL?, selection: Selection?, to outputStream: inout Output
  ) throws {
    let assumedURL = url ?? URL(fileURLWithPath: "source")
    let context = Context(
      configuration: configuration, operatorTable: operatorTable, findingConsumer: findingConsumer,
      fileURL: assumedURL, selection: selection, sourceFileSyntax: syntax, source: source,
      ruleNameCache: ruleNameCache)
    let pipeline = FormatPipeline(context: context)
    let transformedSyntax = pipeline.rewrite(Syntax(syntax))

    if debugOptions.contains(.disablePrettyPrint) {
      outputStream.write(transformedSyntax.description)
      return
    }

    let printer = PrettyPrinter(
      context: context,
      source: source,
      node: transformedSyntax,
      printTokenStream: debugOptions.contains(.dumpTokenStream),
      whitespaceOnly: false)
    outputStream.write(printer.prettyPrint())
  }
}
