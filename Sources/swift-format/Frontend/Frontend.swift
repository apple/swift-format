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
@_spi(Internal) import SwiftFormat
import SwiftSyntax
import SwiftParser

class Frontend {
  /// Represents a file to be processed by the frontend and any file-specific options associated
  /// with it.
  final class FileToProcess {
    /// An open file handle to the source code of the file.
    private let fileHandle: FileHandle

    /// A file URL representing the path to the source file being processed.
    ///
    /// It is the responsibility of the specific frontend to make guarantees about the validity of
    /// this path. For example, the formatting frontend ensures that it is a path to an existing
    /// file only when doing in-place formatting (so that the file can be replaced). In other
    /// situations, it may correspond to a different file than the underlying file handle (if
    /// standard input is used with the `--assume-filename` flag), or it may not be a valid path at
    /// all (the string `"<stdin>"`).
    let url: URL

    /// The configuration that should applied for this file.
    let configuration: Configuration

    /// the selected ranges to process
    let selection: Selection

    /// Returns the string contents of the file.
    ///
    /// The contents of the file are assumed to be UTF-8 encoded. If there is an error decoding the
    /// contents, `nil` will be returned.
    lazy var sourceText: String? = {
      let sourceData = fileHandle.readDataToEndOfFile()
      defer { fileHandle.closeFile() }
      return String(data: sourceData, encoding: .utf8)
    }()

    init(
      fileHandle: FileHandle,
      url: URL,
      configuration: Configuration,
      selection: Selection = .infinite
    ) {
      self.fileHandle = fileHandle
      self.url = url
      self.configuration = configuration
      self.selection = selection
    }
  }

  /// Prints diagnostics to standard error, optionally with color.
  final let diagnosticPrinter: StderrDiagnosticPrinter

  /// The diagnostic engine to which warnings and errors will be emitted.
  final let diagnosticsEngine: DiagnosticsEngine

  /// Options that apply during formatting or linting.
  final let lintFormatOptions: LintFormatOptions

  /// Loads formatter configuration files.
  final var configurationLoader = ConfigurationLoader()

  /// Advanced options that are useful for developing/debugging but otherwise not meant for general
  /// use.
  final var debugOptions: DebugOptions {
    [
      lintFormatOptions.debugDisablePrettyPrint ? .disablePrettyPrint : [],
      lintFormatOptions.debugDumpTokenStream ? .dumpTokenStream : [],
    ]
  }

  /// Creates a new frontend with the given options.
  ///
  /// - Parameter lintFormatOptions: Options that apply during formatting or linting.
  init(lintFormatOptions: LintFormatOptions) {
    self.lintFormatOptions = lintFormatOptions

    self.diagnosticPrinter = StderrDiagnosticPrinter(
      colorMode: lintFormatOptions.colorDiagnostics.map { $0 ? .on : .off } ?? .auto)
    self.diagnosticsEngine =
      DiagnosticsEngine(diagnosticsHandlers: [diagnosticPrinter.printDiagnostic])
  }

  /// Runs the linter or formatter over the inputs.
  final func run() {
    if lintFormatOptions.paths.isEmpty {
      processStandardInput()
    } else {
      processURLs(
        lintFormatOptions.paths.map(URL.init(fileURLWithPath:)),
        parallel: lintFormatOptions.parallel)
    }
  }

  /// Called by the frontend to process a single file.
  ///
  /// Subclasses must override this method to provide the actual linting or formatting logic.
  ///
  /// - Parameter fileToProcess: A `FileToProcess` that contains information about the file to be
  ///   processed.
  func processFile(_ fileToProcess: FileToProcess) {
    fatalError("Must be overridden by subclasses.")
  }

  /// Processes source content from standard input.
  private func processStandardInput() {
    guard let configuration = configuration(
      fromPathOrString: lintFormatOptions.configuration,
      orInferredFromSwiftFileAt: nil)
    else {
      // Already diagnosed in the called method.
      return
    }

    let fileToProcess = FileToProcess(
      fileHandle: FileHandle.standardInput,
      url: URL(fileURLWithPath: lintFormatOptions.assumeFilename ?? "<stdin>"),
      configuration: configuration,
      selection: Selection(offsetRanges: lintFormatOptions.offsets))
    processFile(fileToProcess)
  }

  /// Processes source content from a list of files and/or directories provided as file URLs.
  private func processURLs(_ urls: [URL], parallel: Bool) {
    precondition(
      !urls.isEmpty,
      "processURLs(_:) should only be called when 'urls' is non-empty.")

    if parallel {
      let filesToProcess =
        FileIterator(urls: urls, followSymlinks: lintFormatOptions.followSymlinks)
        .compactMap(openAndPrepareFile)
      DispatchQueue.concurrentPerform(iterations: filesToProcess.count) { index in
        processFile(filesToProcess[index])
      }
    } else {
      FileIterator(urls: urls, followSymlinks: lintFormatOptions.followSymlinks)
        .lazy
        .compactMap(openAndPrepareFile)
        .forEach(processFile)
    }
  }

  /// Read and prepare the file at the given path for processing, optionally synchronizing
  /// diagnostic output.
  private func openAndPrepareFile(at url: URL) -> FileToProcess? {
    guard let sourceFile = try? FileHandle(forReadingFrom: url) else {
      diagnosticsEngine.emitError(
        "Unable to open \(url.relativePath): file is not readable or does not exist")
      return nil
    }

    guard
      let configuration = configuration(
        fromPathOrString: lintFormatOptions.configuration,
        orInferredFromSwiftFileAt: url)
    else {
      // Already diagnosed in the called method.
      return nil
    }

    return FileToProcess(
      fileHandle: sourceFile,
      url: url,
      configuration: configuration,
      selection: Selection(offsetRanges: lintFormatOptions.offsets)
    )
  }

  /// Returns the configuration that applies to the given `.swift` source file, when an explicit
  /// configuration path is also perhaps provided.
  ///
  /// This method also checks for unrecognized rules within the configuration.
  ///
  /// - Parameters:
  ///   - pathOrString: A string containing either the path to a configuration file that will be
  ///     loaded, JSON configuration data directly, or `nil` to try to infer it from
  ///     `swiftFilePath`.
  ///   - swiftFilePath: The path to a `.swift` file, which will be used to infer the path to the
  ///     configuration file if `configurationFilePath` is nil.
  ///
  /// - Returns: If successful, the returned configuration is the one loaded from `pathOrString` if
  ///   it was provided, or by searching in paths inferred by `swiftFilePath` if one exists, or the
  ///   default configuration otherwise. If an error occurred when reading the configuration, a
  ///   diagnostic is emitted and `nil` is returned. If neither `pathOrString` nor `swiftFilePath`
  ///   were provided, a configuration is searched at the current working directory or upwards the
  ///   path. Next the configuration is searched for at the OS default config locations as
  ///   swift-format/config.json. Finally the default `Configuration()` will be returned.
  private func configuration(
    fromPathOrString pathOrString: String?,
    orInferredFromSwiftFileAt swiftFileURL: URL?
  ) -> Configuration? {
    if let pathOrString = pathOrString {
      // If an explicit configuration file path was given, try to load it and fail if it cannot be
      // loaded. (Do not try to fall back to a path inferred from the source file path.)
      let configurationFileURL = URL(fileURLWithPath: pathOrString)
      do {
        let configuration = try configurationLoader.configuration(at: configurationFileURL)
        self.checkForUnrecognizedRules(in: configuration)
        return configuration
      } catch {
        // If we failed to load this from the path, try interpreting the string as configuration
        // data itself because the user might have written something like `--configuration '{...}'`,
        let data = pathOrString.data(using: .utf8)!
        if let configuration = try? Configuration(data: data) {
          return configuration
        }

        // Fail if the configuration flag was neither a valid file path nor valid configuration
        // data.
        diagnosticsEngine.emitError("Unable to read configuration: \(error.localizedDescription)")
        return nil
      }
    }

    // If no explicit configuration file path was given but a `.swift` source file path was given,
    // then try to load the configuration by inferring it based on the source file path.
    if let swiftFileURL = swiftFileURL {
      do {
        if let configuration = try configurationLoader.configuration(forPath: swiftFileURL) {
          self.checkForUnrecognizedRules(in: configuration)
          return configuration
        }
        // Fall through to the default return at the end of the function.
      } catch {
        diagnosticsEngine.emitError(
          "Unable to read configuration for \(swiftFileURL.path): \(error.localizedDescription)")
        return nil
      }
    } else {
      // If reading from stdin and no explicit configuration file was given,
      // walk up the file tree from the cwd to find a config.

      let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
      // Definitely a Swift file. Definitely not a directory. Shhhhhh.
      do {
        if let configuration = try configurationLoader.configuration(forPath: cwd) {
          self.checkForUnrecognizedRules(in: configuration)
          return configuration
        }
      } catch {
        diagnosticsEngine.emitError(
          "Unable to read configuration for \(cwd): \(error.localizedDescription)")
        return nil
      }
    }

    // Load global configuration file
    // First URLs are created, then they are queried. First match is loaded
    var configLocations: [URL] = []

    if #available(macOS 13.0, iOS 16.0, *) {
      // From "~/Library/Application Support/" directory
      configLocations.append(URL.applicationSupportDirectory)
      // From $XDG_CONFIG_HOME directory
      if let xdgConfig: String = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] {
        configLocations.append(URL(filePath: xdgConfig, directoryHint: .isDirectory))
      }
      // From "~/.config/" directory
      var dotconfig: URL = URL.homeDirectory
      dotconfig.append(component: ".config", directoryHint: .isDirectory)
      configLocations.append(dotconfig)
    } else {
      // From "~/Library/Application Support/" directory
      var appSupport: URL = FileManager.default.homeDirectoryForCurrentUser
      appSupport.appendPathComponent("Library", isDirectory: true)
      appSupport.appendPathComponent("Application Support", isDirectory: true)
      configLocations.append(appSupport)
      // From $XDG_CONFIG_HOME directory
      if let xdgConfig: String = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] {
        configLocations.append(URL(fileURLWithPath: xdgConfig))
      }
      // From "~/.config/" directory
      var dotconfig: URL = FileManager.default.homeDirectoryForCurrentUser
      dotconfig.appendPathComponent(".config")
      configLocations.append(dotconfig)
    }

    for var location: URL in configLocations {
      if #available(macOS 13.0, iOS 16.0, *) {
        location.append(components: "swift-format", "config.json")
      } else {
        location.appendPathComponent("swift-format", isDirectory: true)
        location.appendPathComponent("config.json", isDirectory: false)
      }
      if FileManager.default.fileExists(atPath: location.path) {
        do {
          let configuration = try configurationLoader.configuration(at: location)
          self.checkForUnrecognizedRules(in: configuration)
          return configuration
        } catch {
          diagnosticsEngine.emitError(
            "Unable to read configuration for \(location.path): \(error.localizedDescription)")
          return nil
        }
      }
    }

    // An explicit configuration has not been given, and one cannot be found.
    // Return the default configuration.
    return Configuration()
  }

  /// Checks if all the rules in the given configuration are supported by the registry.
  /// If there are any rules that are not supported, they are emitted as a warning.
  private func checkForUnrecognizedRules(in configuration: Configuration) {
    // If any rules in the decoded configuration are not supported by the registry,
    // emit them into the diagnosticsEngine as warnings.
    // That way they will be printed out, but we'll continue execution on the valid rules.
    let invalidRules = configuration.rules.filter { !RuleRegistry.rules.keys.contains($0.key) }
    for rule in invalidRules {
      diagnosticsEngine.emitWarning("Configuration contains an unrecognized rule: \(rule.key)", location: nil)
    }
  }
}
