//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import SwiftDiagnostics
import SwiftFormat
import SwiftSyntax

/// The frontend for formatting operations.
class FormatFrontend: Frontend {
  /// Whether or not to format the Swift file in-place.
  private let inPlace: Bool

  init(lintFormatOptions: LintFormatOptions, inPlace: Bool) {
    self.inPlace = inPlace
    super.init(lintFormatOptions: lintFormatOptions)
  }

  override func processFile(_ fileToProcess: FileToProcess) {
    // In format mode, the diagnostics engine is reserved for fatal messages. Pass nil as the
    // finding consumer to ignore findings emitted while the syntax tree is processed because they
    // will be fixed automatically if they can be, or ignored otherwise.
    let formatter = SwiftFormatter(configuration: fileToProcess.configuration, findingConsumer: nil)
    formatter.debugOptions = debugOptions

    let url = fileToProcess.url
    guard let source = fileToProcess.sourceText else {
      diagnosticsEngine.emitError(
        "Unable to format \(url.relativePath): file is not readable or does not exist.")
      return
    }

    let diagnosticHandler: (SwiftDiagnostics.Diagnostic, SourceLocation) -> () = {
      (diagnostic, location) in
      guard !self.lintFormatOptions.ignoreUnparsableFiles else {
        // No diagnostics should be emitted in this mode.
        return
      }
      self.diagnosticsEngine.consumeParserDiagnostic(diagnostic, location)
    }
    var stdoutStream = FileHandleTextOutputStream(FileHandle.standardOutput)
    do {
      if inPlace {
        var buffer = ""
        try formatter.format(
          source: source,
          assumingFileURL: url,
          to: &buffer,
          parsingDiagnosticHandler: diagnosticHandler)

        if buffer != source {
          let bufferData = Data(buffer.utf8)
          try bufferData.write(to: url, options: .atomic)
        }
      } else {
        try formatter.format(
          source: source,
          assumingFileURL: url,
          to: &stdoutStream,
          parsingDiagnosticHandler: diagnosticHandler)
      }
    } catch SwiftFormatError.fileNotReadable {
      diagnosticsEngine.emitError(
        "Unable to format \(url.relativePath): file is not readable or does not exist.")
      return
    } catch SwiftFormatError.fileContainsInvalidSyntax {
      guard !lintFormatOptions.ignoreUnparsableFiles else {
        guard !inPlace else {
          // For in-place mode, nothing is expected to stdout and the file shouldn't be modified.
          return
        }
        stdoutStream.write(source)
        return
      }
      // Otherwise, relevant diagnostics about the problematic nodes have been emitted.
      return
    } catch {
      diagnosticsEngine.emitError("Unable to format \(url.relativePath): \(error)")
    }
  }
}
