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

/// Common behavior used to generate source files.
protocol FileGenerator {
  /// Types conforming to this protocol must implement this method to write their content into the
  /// given file handle.
  func write(into handle: FileHandle) throws
}

extension FileGenerator {
  /// Generates a file at the given URL, overwriting it if it already exists.
  func generateFile(at url: URL) throws {
    let fm = FileManager.default
    if fm.fileExists(atPath: url.path) {
      try fm.removeItem(at: url)
    }

    fm.createFile(atPath: url.path, contents: nil, attributes: nil)
    let handle = try FileHandle(forWritingTo: url)
    defer { handle.closeFile() }

    try write(into: handle)
  }
}

extension FileHandle: TextOutputStream {
  /// Writes the provided string as data to a file output stream.
  public func write(_ string: String) {
    let data = Data(string.utf8)
    write(data)
  }
}
