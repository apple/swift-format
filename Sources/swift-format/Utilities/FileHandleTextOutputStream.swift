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

/// Wraps a `FileHandle` so that it can be used by APIs that take a `TextOutputStream`-conforming
/// type as an input.
struct FileHandleTextOutputStream: TextOutputStream {
  /// The underlying file handle to which the text will be written.
  private var fileHandle: FileHandle

  /// Creates a new output stream that writes to the given file handle.
  init(_ fileHandle: FileHandle) {
    self.fileHandle = fileHandle
  }

  func write(_ string: String) {
    let data = Data(string.utf8)
    fileHandle.write(data)
  }
}
