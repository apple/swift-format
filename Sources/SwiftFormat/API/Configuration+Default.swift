//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

extension Configuration {
  /// Creates a new `Configuration` with default values.
  ///
  /// This initializer is isolated to its own file to make it easier for users who are forking or
  /// building swift-format themselves to hardcode a different default configuration. To do this,
  /// simply replace this file with your own default initializer that sets the values to whatever
  /// you want.
  ///
  /// When swift-format reads a configuration file from disk, any values that are not specified in
  /// the JSON will be populated from this default configuration.
  public init() {
    self.rules = Self.defaultRuleEnablements
    self.maximumBlankLines = 1
    self.lineLength = 100
    self.tabWidth = 8
    self.indentation = .spaces(2)
    self.respectsExistingLineBreaks = true
    self.lineBreakBeforeControlFlowKeywords = false
    self.lineBreakBeforeEachArgument = false
    self.lineBreakBeforeEachGenericRequirement = false
    self.prioritizeKeepingFunctionOutputTogether = false
    self.indentConditionalCompilationBlocks = true
    self.lineBreakAroundMultilineExpressionChainComponents = false
    self.fileScopedDeclarationPrivacy = FileScopedDeclarationPrivacyConfiguration()
    self.indentSwitchCaseLabels = false
    self.spacesAroundRangeFormationOperators = false
    self.noAssignmentInExpressions = NoAssignmentInExpressionsConfiguration()
    self.multiElementCollectionTrailingCommas = true
    self.wrapComments = false
    self.maximumCommentTextWidth = 72
  }
}
