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
import Markdown
import SwiftSyntax

/// Documentation comments must be complete and valid.
///
/// "Command + Option + /" in Xcode produces a minimal valid documentation comment.
///
/// Lint: Documentation comments that are incomplete (e.g. missing parameter documentation) or
///       invalid (uses `Parameters` when there is only one parameter) will yield a lint error.
@_spi(Rules)
public final class ValidateDocumentationComments: SyntaxLintRule {
  /// Identifies this rule as being opt-in. Accurate and complete documentation comments are
  /// important, but this rule isn't able to handle situations where portions of documentation are
  /// redundant. For example when the returns clause is redundant for a simple declaration.
  public override class var isOptIn: Bool { return true }

  public override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
    return checkFunctionLikeDocumentation(
      DeclSyntax(node), name: "init", signature: node.signature)
  }

  public override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
    return checkFunctionLikeDocumentation(
      DeclSyntax(node), name: node.name.text, signature: node.signature,
      returnClause: node.signature.returnClause)
  }

  private func checkFunctionLikeDocumentation(
    _ node: DeclSyntax,
    name: String,
    signature: FunctionSignatureSyntax,
    returnClause: ReturnClauseSyntax? = nil
  ) -> SyntaxVisitorContinueKind {
    guard
      let docComment = DocumentationComment(extractedFrom: node),
      !docComment.parameters.isEmpty
    else {
      return .skipChildren
    }

    // If a single sentence summary is the only documentation, parameter(s) and
    // returns tags may be omitted.
    if docComment.briefSummary != nil
      && docComment.bodyNodes.isEmpty
      && docComment.parameters.isEmpty
      && docComment.returns == nil
    {
      return .skipChildren
    }

    validateThrows(
      signature.effectSpecifiers?.throwsClause?.throwsSpecifier,
      name: name,
      throwsDescription: docComment.throws,
      node: node)
    validateReturn(
      returnClause,
      name: name,
      returnsDescription: docComment.returns,
      node: node)
    let funcParameters = funcParametersIdentifiers(in: signature.parameterClause.parameters)

    // If the documentation of the parameters is wrong 'docCommentInfo' won't
    // parse the parameters correctly. First the documentation has to be fix
    // in order to validate the other conditions.
    if docComment.parameterLayout != .separated && funcParameters.count == 1 {
      diagnose(.useSingularParameter, on: node)
      return .skipChildren
    } else if docComment.parameterLayout != .outline && funcParameters.count > 1 {
      diagnose(.usePluralParameters, on: node)
      return .skipChildren
    }

    // Ensures that the parameters of the documentation and the function signature
    // are the same.
    if (docComment.parameters.count != funcParameters.count)
      || !parametersAreEqual(params: docComment.parameters, funcParam: funcParameters)
    {
      diagnose(.parametersDontMatch(funcName: name), on: node)
    }

    return .skipChildren
  }

  /// Ensures the function has a return documentation if it actually returns
  /// a value.
  private func validateReturn(
    _ returnClause: ReturnClauseSyntax?,
    name: String,
    returnsDescription: Paragraph?,
    node: DeclSyntax
  ) {
    if returnClause == nil && returnsDescription != nil {
      diagnose(.removeReturnComment(funcName: name), on: node)
    } else if let returnClause = returnClause, returnsDescription == nil {
      if let returnTypeIdentifier = returnClause.type.as(IdentifierTypeSyntax.self),
         returnTypeIdentifier.name.text == "Never"
      {
        return
      }
      diagnose(.documentReturnValue(funcName: name), on: returnClause)
    }
  }

  /// Ensures the function has throws documentation if it may actually throw
  /// an error.
  private func validateThrows(
    _ throwsOrRethrowsKeyword: TokenSyntax?,
    name: String,
    throwsDescription: Paragraph?,
    node: DeclSyntax
  ) {
    // If a function is marked as `rethrows`, it doesn't have any errors of its
    // own that should be documented. So only require documentation for
    // functions marked `throws`.
    let needsThrowsDesc = throwsOrRethrowsKeyword?.tokenKind == .keyword(.throws)

    if !needsThrowsDesc && throwsDescription != nil {
      diagnose(
        .removeThrowsComment(funcName: name),
        on: throwsOrRethrowsKeyword ?? node.firstToken(viewMode: .sourceAccurate))
    } else if needsThrowsDesc && throwsDescription == nil {
      diagnose(.documentErrorsThrown(funcName: name), on: throwsOrRethrowsKeyword)
    }
  }
}

/// Iterates through every parameter of paramList and returns a list of the
/// parameters identifiers.
fileprivate func funcParametersIdentifiers(in paramList: FunctionParameterListSyntax) -> [String] {
  var funcParameters = [String]()
  for parameter in paramList {
    // If there is a label and an identifier, then the identifier (`secondName`) is the name that
    // should be documented. Otherwise, the label and identifier are the same, occupying
    // `firstName`.
    let parameterIdentifier = parameter.secondName ?? parameter.firstName
    funcParameters.append(parameterIdentifier.text)
  }
  return funcParameters
}

/// Indicates if the parameters name from the documentation and the parameters
/// from the declaration are the same.
fileprivate func parametersAreEqual(
  params: [DocumentationComment.Parameter],
  funcParam: [String]
) -> Bool {
  for index in 0..<params.count {
    if params[index].name != funcParam[index] {
      return false
    }
  }
  return true
}

extension Finding.Message {
  fileprivate static func documentReturnValue(funcName: String) -> Finding.Message {
    "add a 'Returns:' section to document the return value of '\(funcName)'"
  }

  fileprivate static func removeReturnComment(funcName: String) -> Finding.Message {
    "remove the 'Returns:' section of '\(funcName)'; it does not return a value"
  }

  fileprivate static func parametersDontMatch(funcName: String) -> Finding.Message {
    "change the parameters of the documentation of '\(funcName)' to match its parameters"
  }

  fileprivate static let useSingularParameter: Finding.Message =
    "replace the plural 'Parameters:' section with a singular inline 'Parameter' section"

  fileprivate static let usePluralParameters: Finding.Message =
    """
    replace the singular inline 'Parameter' section with a plural 'Parameters:' section \
    that has the parameters nested inside it
    """

  fileprivate static func removeThrowsComment(funcName: String) -> Finding.Message {
    "remove the 'Throws:' sections of '\(funcName)'; it does not throw any errors"
  }

  fileprivate static func documentErrorsThrown(funcName: String) -> Finding.Message {
    "add a 'Throws:' section to document the errors thrown by '\(funcName)'"
  }
}
