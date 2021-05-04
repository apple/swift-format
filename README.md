# swift-format


`swift-format` provides the formatting technology for
[SourceKit-LSP](https://github.com/apple/sourcekit-lsp) and the building
blocks for doing code formatting transformations.

This package can be used as a [command line tool](#command-line-usage)
or linked into other applications as a Swift Package Manager dependency and
invoked via an [API](#api-usage).

> NOTE: No default Swift code style guidelines have yet been proposed. The
> style that is currently applied by `swift-format` is just one possibility,
> and the code is provided so that it can be tested on real-world code and
> experiments can be made by modifying it.

## Matching swift-format to Your Swift Version

`swift-format` depends on [SwiftSyntax](https://github.com/apple/swift-syntax)
and the standalone parsing library that is distributed as part of the Swift
toolchain. The SwiftSyntax version in use must match the toolchain version, so
you should check out and build `swift-format` from the branch that is
compatible with the version of Swift you are using. This version dependency
is also expressed in the `SwiftSyntax` dependency in
[Package.swift](Package.swift).

| Xcode Release | Swift Version                           | `swift-format` Branch |
|:-------------:|:---------------------------------------:|:----------------------|
| –             | Swift at `main`                         | `main`                |
| Xcode 12.0    | Swift 5.3                               | `swift-5.3-branch`    |
| Xcode 11.4    | Swift 5.2                               | `swift-5.2-branch`    |
| Xcode 11.0    | Swift 5.1                               | `swift-5.1-branch`    |

For example, if you are using Xcode 12.0 (Swift 5.3), you can check out and
build `swift-format` using the following commands:

```
git clone -b swift-5.3-branch https://github.com/apple/swift-format.git
cd swift-format
swift build
```

You can also add the `--single-branch` option if you only want to clone that
specific branch.

The `main` branch is used for development and may depend on either a release
version of Swift or on a developer snapshot. Changes committed to `main`
that are compatible with the latest release branch will be cherry-picked into
that branch.

To test that the formatter was built succesfully and is compatible with your
Swift toolchain, you can run the following command:

```
swift test --parallel
```
We recommend using the `--parallel` flag to speed up the test run since there
are a large number of tests.

## Command Line Usage

```
swift-format [OPTIONS] FILE...
```

The `swift-format` tool can be invoked with one or more `.swift` source files,
as well as the following command line options:

* `-v/--version`: Prints the `swift-format` version and exits.

* `-m/--mode <format|lint|dump-configuration>`: The mode in which to run
  `swift-format`. The `format` mode formats source files. The `lint` mode
  only prints diagnostics indicating style violations. The `dump-configuration`
  mode dumps the default `swift-format` configuration to standard output.

  If unspecified, the default mode is `format`.

* `--configuration <file>`: The path to a JSON file that contains
  [configurable settings](#configuration) for `swift-format`. If omitted, a
  default configuration is use (which can be seen by running
  `--mode dump-configuration`).

* `-i/--in-place`: Overwrites the input files when formatting instead of
  printing the results to standard output.

* `-p/--parallel`: Process files in parallel, simultaneously across
  multiple cores.

* `-r/--recursive`: If specified, then the tool will process `.swift` source
  files in any directories listed on the command line and their descendants.
  Without this flag, it is an error to list a directory on the command line.

### Configuration

For any source file being checked or formatted, `swift-format` looks for a
JSON-formatted file named `.swift-format` in the same directory. If one is
found, then that file is loaded to determine the tool's configuration. If the
file is not found, then it looks in the parent directory, and so on.

If no configuration file is found, a default configuration is used. The
settings in the default configuration can be viewed by running
`swift-format --mode dump-configuration`, which will dump it to standard
output.

If the `--configuration <file>` option is passed to `swift-format`, then that
configuration will be used unconditionally and the file system will not be
searched.

See [Documentation/Configuration.md](Documentation/Configuration.md) for a
description of the configuration file format and the settings that are
available.

## API Usage

`swift-format` can be easily integrated into other tools written in Swift.
Instead of invoking the formatter by spawning a subprocess, users can depend on
`swift-format` as a Swift Package Manager dependency and import the
`SwiftFormat` module, which contains the entry points into the formatter's
diagnostic and correction behavior.

Formatting behavior is provided by the `SwiftFormatter` class and linting
behavior is provided by the `SwiftLinter` class. These APIs can be passed
either a Swift source file `URL` or a `Syntax` node representing a
SwiftSyntax syntax tree. The latter capability is particularly useful for
writing code generators, since it significantly reduces the amount of trivia
that the generator needs to be concerned about adding to the syntax nodes it
creates. Instead, it can pass the in-memory syntax tree to the `SwiftFormat`
API and receive perfectly formatted code as output.

Please see the documentation in the
[`SwiftFormatter`](Sources/SwiftFormat/SwiftFormatter.swift) and
[`SwiftLinter`](Sources/SwiftFormat/SwiftLinter.swift) classes for more
information about their usage.

## Development

If you are interested in developing `swift-format`, there is additional
documentation about that [here](Documentation/Development.md).
