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
import SwiftDiagnostics
import SwiftOperators
import SwiftSyntax

/// Diagnoses and reports problems in Swift source code or syntax trees according to the Swift style
/// guidelines.
public final class SwiftLinter {

  /// The configuration settings that control the linter's behavior.
  public let configuration: Configuration

  /// A callback that will be notified with any findings encountered during linting.
  public let findingConsumer: (Finding) -> Void

  /// Advanced options that are useful when debugging the linter's behavior but are not meant for
  /// general use.
  public var debugOptions: DebugOptions = []

  /// Creates a new Swift code linter with the given configuration.
  ///
  /// - Parameters:
  ///   - configuration: The configuration settings that control the linter's behavior.
  ///   - findingConsumer: A callback that will be notified with any findings encountered during
  ///     linting.
  public init(configuration: Configuration, findingConsumer: @escaping (Finding) -> Void) {
    self.configuration = configuration
    self.findingConsumer = findingConsumer
  }

  /// Lints the Swift code at the given file URL.
  ///
  /// This form of the `lint` function automatically folds expressions using the default operator
  /// set defined in Swift. If you need more control over this—for example, to provide the correct
  /// precedence relationships for custom operators—you must parse and fold the syntax tree
  /// manually and then call ``lint(syntax:assumingFileURL:)``.
  ///
  /// - Parameters:
  ///   - url: The URL of the file containing the code to format.
  ///   - parsingDiagnosticHandler: An optional callback that will be notified if there are any
  ///     errors when parsing the source code.
  /// - Throws: If an unrecoverable error occurs when formatting the code.
  public func lint(
    contentsOf url: URL,
    parsingDiagnosticHandler: ((Diagnostic, SourceLocation) -> Void)? = nil
  ) throws {
    guard FileManager.default.isReadableFile(atPath: url.path) else {
      throw SwiftFormatError.fileNotReadable
    }
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
      throw SwiftFormatError.isDirectory
    }

    try lint(
      source: String(contentsOf: url, encoding: .utf8),
      assumingFileURL: url,
      parsingDiagnosticHandler: parsingDiagnosticHandler)
  }

  /// Lints the given Swift source code.
  ///
  /// This form of the `lint` function automatically folds expressions using the default operator
  /// set defined in Swift. If you need more control over this—for example, to provide the correct
  /// precedence relationships for custom operators—you must parse and fold the syntax tree
  /// manually and then call ``lint(syntax:assumingFileURL:)``.
  ///
  /// - Parameters:
  ///   - source: The Swift source code to be linted.
  ///   - url: A file URL denoting the filename/path that should be assumed for this source code.
  ///   - parsingDiagnosticHandler: An optional callback that will be notified if there are any
  ///     errors when parsing the source code.
  /// - Throws: If an unrecoverable error occurs when formatting the code.
  public func lint(
    source: String,
    assumingFileURL url: URL,
    parsingDiagnosticHandler: ((Diagnostic, SourceLocation) -> Void)? = nil
  ) throws {
    // If the file or input string is completely empty, do nothing. This prevents even a trailing
    // newline from being diagnosed for an empty file. (This is consistent with clang-format, which
    // also does not touch an empty file even if the setting to add trailing newlines is enabled.)
    guard !source.isEmpty else { return }

    let sourceFile = try parseAndEmitDiagnostics(
      source: source,
      operatorTable: .standardOperators,
      assumingFileURL: url,
      parsingDiagnosticHandler: parsingDiagnosticHandler)
    try lint(
      syntax: sourceFile, operatorTable: .standardOperators, assumingFileURL: url, source: source)
  }

  /// Lints the given Swift syntax tree.
  ///
  /// This form of the `lint` function does not perform any additional processing on the given
  /// syntax tree. The tree **must** have all expressions folded using an `OperatorTable`, and no
  /// detection of warnings/errors is performed.
  ///
  /// - Note: The linter may be faster using the source text, if it's available.
  ///
  /// - Parameters:
  ///   - syntax: The Swift syntax tree to be converted to be linted.
  ///   - operatorTable: The table that defines the operators and their precedence relationships.
  ///     This must be the same operator table that was used to fold the expressions in the `syntax`
  ///     argument.
  ///   - url: A file URL denoting the filename/path that should be assumed for this syntax tree.
  /// - Throws: If an unrecoverable error occurs when formatting the code.
  public func lint(
    syntax: SourceFileSyntax,
    source: String,
    operatorTable: OperatorTable,
    assumingFileURL url: URL
  ) throws {
    try lint(syntax: syntax, operatorTable: operatorTable, assumingFileURL: url, source: source)
  }

  private func lint(
    syntax: SourceFileSyntax,
    operatorTable: OperatorTable,
    assumingFileURL url: URL,
    source: String
  ) throws {
    let context = Context(
      configuration: configuration, operatorTable: operatorTable, findingConsumer: findingConsumer,
      fileURL: url, sourceFileSyntax: syntax, source: source, ruleNameCache: ruleNameCache)
    let pipeline = LintPipeline(context: context)
    pipeline.walk(Syntax(syntax))

    if debugOptions.contains(.disablePrettyPrint) {
      return
    }

    // Perform whitespace linting by comparing the input source text with the output of the
    // pretty-printer.
    let printer = PrettyPrinter(
      context: context,
      source: source,
      node: Syntax(syntax),
      printTokenStream: debugOptions.contains(.dumpTokenStream),
      whitespaceOnly: true)
    let formatted = printer.prettyPrint()
    let ws = WhitespaceLinter(user: syntax.description, formatted: formatted, context: context)
    ws.lint()
  }
}
