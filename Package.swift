// swift-tools-version:5.6
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
import PackageDescription

let package = Package(
  name: "swift-format",
  platforms: [
    .macOS("12.0"),
    .iOS("13.0")
  ],
  products: [
    .executable(
      name: "swift-format",
      targets: ["swift-format"]
    ),
    .library(
      name: "SwiftFormat",
      targets: ["SwiftFormat"]
    ),
    .plugin(
      name: "FormatPlugin",
      targets: ["Format Source Code"]
    ),
    .plugin(
      name: "FormatBuildPlugin",
      targets: ["Format Build Plugin"]
    ),
    .plugin(
      name: "LintPlugin",
      targets: ["Lint Source Code"]
    ),
    .plugin(
      name: "LintBuildPlugin",
      targets: ["Lint Build Plugin"]
    )
  ],
  dependencies: dependencies,
  targets: [
    .target(
      name: "_SwiftFormatInstructionCounter"
    ),

    .target(
      name: "SwiftFormat",
      dependencies: [
        .product(name: "Markdown", package: "swift-markdown"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
        .product(name: "SwiftOperators", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftParserDiagnostics", package: "swift-syntax"),
      ]
    ),
    .target(
      name: "_SwiftFormatTestSupport",
      dependencies: [
        "SwiftFormat",
        .product(name: "SwiftOperators", package: "swift-syntax"),
      ]
    ),
    .plugin(
      name: "Format Source Code",
      capability: .command(
        intent: .sourceCodeFormatting(),
        permissions: [
          .writeToPackageDirectory(reason: "This command formats the Swift source files")
        ]
      ),
      dependencies: [
        .target(name: "swift-format")
      ],
      path: "Plugins/FormatPlugin"
    ),
    .plugin(
      name: "Format Build Plugin",
      capability: .buildTool(),
      dependencies: [
          .target(name: "swift-format")
      ],
      path: "Plugins/FormatBuildPlugin"
    ),
    .plugin(
      name: "Lint Source Code",
      capability: .command(
        intent: .custom(
          verb: "lint-source-code",
          description: "Lint source code for a specified target."
        )
      ),
      dependencies: [
        .target(name: "swift-format")
      ],
      path: "Plugins/LintPlugin"
    ),
    .plugin(
        name: "Lint Build Plugin",
        capability: .buildTool(),
        dependencies: [
            .target(name: "swift-format")
        ],
        path: "Plugins/LintBuildPlugin"
    ),
    .executableTarget(
      name: "generate-swift-format",
      dependencies: [
        "SwiftFormat",
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    .executableTarget(
      name: "swift-format",
      dependencies: [
        "_SwiftFormatInstructionCounter",
        "SwiftFormat",
        .product(name: "ArgumentParser", package: "swift-argument-parser"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ],
      linkerSettings: swiftformatLinkSettings
    ),
    .testTarget(
      name: "SwiftFormatPerformanceTests",
      dependencies: [
        "SwiftFormat",
        "_SwiftFormatTestSupport",
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "SwiftFormatTests",
      dependencies: [
        "SwiftFormat",
        "_SwiftFormatTestSupport",
        .product(name: "Markdown", package: "swift-markdown"),
        .product(name: "SwiftOperators", package: "swift-syntax"),
        .product(name: "SwiftParser", package: "swift-syntax"),
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
      ]
    ),
    .testTarget(
      name: "swift-formatTests",
      dependencies: ["swift-format"]
    ),
  ]
)

// MARK: - Parse build arguments

func hasEnvironmentVariable(_ name: String) -> Bool {
  return ProcessInfo.processInfo.environment[name] != nil
}

// When building the toolchain on the CI, don't add the CI's runpath for the
// final build before installing.
var installAction: Bool { hasEnvironmentVariable("SWIFTFORMAT_CI_INSTALL") }

/// Assume that all the package dependencies are checked out next to sourcekit-lsp and use that instead of fetching a
/// remote dependency.
var useLocalDependencies: Bool { hasEnvironmentVariable("SWIFTCI_USE_LOCAL_DEPS") }

// MARK: - Dependencies

var dependencies: [Package.Dependency] {
  if useLocalDependencies {
    return [
      .package(path: "../swift-argument-parser"),
      .package(path: "../swift-markdown"),
      .package(path: "../swift-syntax"),
    ]
  } else {
    return [
      .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.2"),
      .package(url: "https://github.com/apple/swift-markdown.git", from: "0.2.0"),
      .package(url: "https://github.com/swiftlang/swift-syntax.git", branch: "main"),
    ]
  }
}



// MARK: - Compute custom build settings

var swiftformatLinkSettings: [LinkerSetting]  {
  if installAction {
    return [.unsafeFlags(["-no-toolchain-stdlib-rpath"], .when(platforms: [.linux, .android]))]
  } else {
    return []
  }
}

