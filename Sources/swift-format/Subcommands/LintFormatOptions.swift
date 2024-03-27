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

import ArgumentParser
import Foundation

/// Common arguments used by the `lint` and `format` subcommands.
struct LintFormatOptions: ParsableArguments {
  /// The path to the JSON configuration file that should be loaded.
  ///
  /// If not specified, the default configuration will be used.
  @Option(
    name: .customLong("configuration"),
    help: """
      The path to a JSON file containing the configuration of the linter/formatter or a JSON \
      string containing the configuration directly.
      """)
  var configuration: String?

  /// A JSON string containing the selected ranges to process.
  ///
  /// If not specified, the whole file will be formatted.
  @Option(
    name: .long,
    help: """
      A JSON string containing an array of {"offset":<Int>, "length":<Int>} pairs specifying \
      the source code ranges to format.
      """)
  var selection: String?


  /// The filename for the source code when reading from standard input, to include in diagnostic
  /// messages.
  ///
  /// If not specified and standard input is used, a dummy filename is used for diagnostic messages
  /// about the source from standard input.
  @Option(help: "When using standard input, the filename of the source to include in diagnostics.")
  var assumeFilename: String?

  /// Whether or not to run the formatter/linter recursively.
  ///
  /// If set, we recursively run on all ".swift" files in any provided directories.
  @Flag(
    name: .shortAndLong,
    help: "Recursively run on '.swift' files in any provided directories.")
  var recursive: Bool = false

  /// Whether unparsable files, due to syntax errors or unrecognized syntax, should be ignored or
  /// treated as containing an error. When ignored, unparsable files are output verbatim in format
  /// mode and no diagnostics are raised in lint mode. When not ignored, unparsable files raise a
  /// diagnostic in both format and lint mode.
  @Flag(help: """
    Ignores unparsable files, disabling all diagnostics and formatting for files that contain \
    invalid syntax.
    """)
  var ignoreUnparsableFiles: Bool = false

  /// Whether or not to run the formatter/linter in parallel.
  @Flag(
    name: .shortAndLong,
    help: "Process files in parallel, simultaneously across multiple cores.")
  var parallel: Bool = false

  /// Whether colors should be used in diagnostics printed to standard error.
  ///
  /// If nil, color usage will be automatically detected based on whether standard error is
  /// connected to a terminal or not.
  @Flag(
    inversion: .prefixedNo,
    help: """
      Enables or disables color diagnostics when printing to standard error. The default behavior \
      if this flag is omitted is to use colors if standard error is connected to a terminal, and \
      to not use colors otherwise.
      """)
  var colorDiagnostics: Bool?

  /// Whether symlinks should be followed.
  @Flag(help: """
    Follow symbolic links passed on the command line, or found during directory traversal when \
    using `-r/--recursive`.
    """)
  var followSymlinks: Bool = false

  /// The list of paths to Swift source files that should be formatted or linted.
  @Argument(help: "Zero or more input filenames.")
  var paths: [String] = []

  @Flag(help: .hidden) var debugDisablePrettyPrint: Bool = false
  @Flag(help: .hidden) var debugDumpTokenStream: Bool = false

  mutating func validate() throws {
    if recursive && paths.isEmpty {
      throw ValidationError("'--recursive' is only valid when formatting or linting files")
    }

    if assumeFilename != nil && !paths.isEmpty {
      throw ValidationError("'--assume-filename' is only valid when reading from stdin")
    }

    if selection != nil && paths.count > 1 {
      throw ValidationError("'--selection' is only valid when processing a single file")
    }

    if !paths.isEmpty && !recursive {
      for path in paths {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
          throw ValidationError(
            """
            '\(path)' is a path to a directory, not a Swift source file.
            Use the '--recursive' option to handle directories.
            """
          )
        }
      }
    }
  }
}
