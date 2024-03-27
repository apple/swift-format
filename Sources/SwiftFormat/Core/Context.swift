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
import SwiftOperators
import SwiftSyntax
import SwiftParser

/// Context contains the bits that each formatter and linter will need access to.
///
/// Specifically, it is the container for the shared configuration, diagnostic consumer, and URL of
/// the current file.
@_spi(Rules)
public final class Context {

  /// Tracks whether `XCTest` has been imported so that certain logic can be modified for files that
  /// are known to be tests.
  public enum XCTestImportState {

    /// Whether `XCTest` is imported or not has not yet been determined.
    case notDetermined

    /// The file is known to import `XCTest`.
    case importsXCTest

    /// The file is known to not import `XCTest`.
    case doesNotImportXCTest
  }

  /// The configuration for this run of the pipeline, provided by a configuration JSON file.
  let configuration: Configuration

  /// The optional ranges to process
  let selection: Selection?

  /// Defines the operators and their precedence relationships that were used during parsing.
  let operatorTable: OperatorTable

  /// Emits findings to the finding consumer.
  let findingEmitter: FindingEmitter

  /// The URL of the file being linted or formatted.
  let fileURL: URL

  /// Indicates whether the file is known to import XCTest.
  public var importsXCTest: XCTestImportState

  /// An object that converts `AbsolutePosition` values to `SourceLocation` values.
  public let sourceLocationConverter: SourceLocationConverter

  /// Contains the rules have been disabled by comments for certain line numbers.
  let ruleMask: RuleMask

  /// Contains all the available rules' names associated to their types' object identifiers.
  let ruleNameCache: [ObjectIdentifier: String]

  /// Creates a new Context with the provided configuration, diagnostic engine, and file URL.
  public init(
    configuration: Configuration,
    operatorTable: OperatorTable,
    findingConsumer: ((Finding) -> Void)?,
    fileURL: URL,
    selection: Selection? = nil,
    sourceFileSyntax: SourceFileSyntax,
    source: String? = nil,
    ruleNameCache: [ObjectIdentifier: String]
  ) {
    self.configuration = configuration
    self.operatorTable = operatorTable
    self.findingEmitter = FindingEmitter(consumer: findingConsumer)
    self.fileURL = fileURL
    self.selection = selection
    self.importsXCTest = .notDetermined
    let tree = source.map { Parser.parse(source: $0) } ?? sourceFileSyntax
    self.sourceLocationConverter =
      SourceLocationConverter(fileName: fileURL.relativePath, tree: tree)
    self.ruleMask = RuleMask(
      syntaxNode: Syntax(sourceFileSyntax),
      sourceLocationConverter: sourceLocationConverter
    )
    self.ruleNameCache = ruleNameCache
  }

  /// Given a rule's name and the node it is examining, determine if the rule is disabled at this
  /// location or not. Also makes sure the entire node is contained inside any selection.
  func isRuleEnabled<R: Rule>(_ rule: R.Type, node: Syntax) -> Bool {
    guard node.isInsideSelection(selection) else { return false }

    let loc = node.startLocation(converter: self.sourceLocationConverter)

    assert(
      ruleNameCache[ObjectIdentifier(rule)] != nil,
      """
      Missing cached rule name for '\(rule)'! \
      Ensure `generate-swift-format` has been run and `ruleNameCache` was injected.
      """)

    let ruleName = ruleNameCache[ObjectIdentifier(rule)] ?? R.ruleName
    switch ruleMask.ruleState(ruleName, at: loc) {
    case .default:
      return configuration.rules[ruleName] ?? false
    case .disabled:
      return false
    }
  }
}
