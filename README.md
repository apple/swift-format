# swift-format

`swift-format` provides the formatting technology for
[SourceKit-LSP](https://github.com/swiftlang/sourcekit-lsp) and the building
blocks for doing code formatting transformations.

This package can be used as a [command line tool](#command-line-usage)
or linked into other applications as a Swift Package Manager dependency and
invoked via an [API](#api-usage).

> NOTE: No default Swift code style guidelines have yet been proposed. The
> style that is currently applied by `swift-format` is just one possibility,
> and the code is provided so that it can be tested on real-world code and
> experiments can be made by modifying it.

## Matching swift-format to Your Swift Version

### Swift 5.8 and later

As of Swift 5.8, swift-format depends on the version of
[SwiftSyntax](https://github.com/swiftlang/swift-syntax) whose parser has been
rewritten in Swift and no longer has dependencies on libraries in the
Swift toolchain.

This change allows `swift-format` to be built, developed, and run using
any version of Swift that can compile it, decoupling it from the version
that supported a particular syntax. However, earlier versions of swift-format
will still not be able to recognize new syntax added in later versions of the
language and parser.

Note also that the version numbering scheme has changed to match
SwiftSyntax; the 5.8 release of swift-format is `508.0.0`, not `0.50800.0`.

### Swift 5.7 and earlier

`swift-format` versions 0.50700.0 and earlier depend on versions of
[SwiftSyntax](https://github.com/swiftlang/swift-syntax) that used a standalone
parsing library distributed as part of the Swift toolchain. When using these
versions, you should check out and build `swift-format` from the release
tag or branch that is compatible with the version of Swift you are using.

The major and minor version components of `swift-format` and SwiftSyntax must
be the same—this is expressed in the `SwiftSyntax` dependency in
[Package.swift](Package.swift)—and those version components must match the
Swift toolchain that is installed and used to build and run the formatter:

| Xcode Release   | Swift Version          | `swift-format` Branch / Tags     |
|:----------------|:-----------------------|:---------------------------------|
| –               | Swift at `main`        | `main`                           |
| Xcode 14.0      | Swift 5.7              | `release/5.7` / `0.50700.x`      |
| Xcode 13.3      | Swift 5.6              | `release/5.6` / `0.50600.x`      |
| Xcode 13.0–13.2 | Swift 5.5              | `swift-5.5-branch` / `0.50500.x` |
| Xcode 12.5      | Swift 5.4              | `swift-5.4-branch` / `0.50400.x` |
| Xcode 12.0–12.4 | Swift 5.3              | `swift-5.3-branch` / `0.50300.x` |
| Xcode 11.4–11.7 | Swift 5.2              | `swift-5.2-branch` / `0.50200.x` |
| Xcode 11.0–11.3 | Swift 5.1              | `swift-5.1-branch`               |

For example, if you are using Xcode 13.3 (Swift 5.6), you will need
`swift-format` 0.50600.0.

## Getting swift-format

If you are mainly interested in using swift-format (rather than developing it),
then you can get it in three different ways:

### Included in Xcode

Xcode 16 and above include swift-format in the toolchain. You can run `swift-format` from anywhere on the system using `swift format` (notice the space instead of dash). To find the path at which `swift-format` is installed, run `xcrun --find swift-format`.

### Installing via Homebrew

Run `brew install swift-format` to install the latest version.

### Building from source

Install `swift-format` using the following commands:

```sh
VERSION=510.1.0  # replace this with the version you need
git clone https://github.com/swiftlang/swift-format.git
cd swift-format
git checkout "tags/$VERSION"
swift build -c release
```

Note that the `git checkout` command above will leave the repository in a
"detached HEAD" state. This is fine if building and running the tool is all you
want to do.

Once the build has finished, the `swift-format` executable will be located at
`.build/release/swift-format`.

To test that the formatter was built successfully and is compatible with your
Swift toolchain, you can also run the following command:

```sh
swift test --parallel
```

We recommend using the `--parallel` flag to speed up the test run since there
are a large number of tests.

## Command Line Usage

The general invocation syntax for `swift-format` is as follows:

```sh
swift-format [SUBCOMMAND] [OPTIONS...] [FILES...]
```

The tool supports a number of subcommands, each of which has its own options
and are described below. Descriptions of the subcommands that are available
can also be obtained by running `swift-format --help`, and the description of
a specific subcommand can be obtained by using the `--help` flag after the
subcommand name; for example, `swift-format lint --help`.

### Formatting

```sh
swift-format [format] [OPTIONS...] [FILES...]
```

The `format` subcommand formats one or more Swift source files (or source code
from standard input if no file paths are given on the command line). Writing
out the `format` subcommand is optional; it is the default behavior if no other
subcommand is given.

This subcommand supports all of the
[common lint and format options](#options-supported-by-formatting-and-linting),
as well as the formatting-only options below:

*   `-i/--in-place`: Overwrites the input files when formatting instead of
    printing the results to standard output. _No backup of the original file is
    made before it is overwritten._

### Linting

```sh
swift-format lint [OPTIONS...] [FILES...]
```

The `lint` subcommand checks one or more Swift source files (or source code
from standard input if no file paths are given on the command line) for style
violations and prints diagnostics to standard error for any violations that
are detected.

This subcommand supports all of the
[common lint and format options](#options-supported-by-formatting-and-linting),
as well as the linting-only options below:

*   `-s/--strict`: If this option is specified, lint warnings will cause the
    tool to exit with a non-zero exit code (failure). By default, lint warnings
    do not prevent a successful exit; only fatal errors (for example, trying to
    lint a file that does not exist) cause the tool to exit unsuccessfully.

### Options Supported by Formatting and Linting

The following options are supported by both the `format` and `lint`
subcommands:

*   `--assume-filename <path>`: The file path that should be used in
    diagnostics when linting or formatting from standard input. If this option
    is not provided, then `<stdin>` will be used as the filename printed in
    diagnostics.

*   `--color-diagnostics/--no-color-diagnostics`: By default, `swift-format`
    will print diagnostics in color if standard error is connected to a
    terminal and without color otherwise (for example, if standard error is
    being redirected to a file). These flags can be used to force colors on
    or off respectively, regardless of whether the output is going to a
    terminal.

*   `--configuration <file|string>`: The path to a JSON file that contains
    [configurable settings](#configuring-the-command-line-tool) for
    `swift-format`. If no file is found, `swift-format` tries to load the json
    data as a string, if valid. If the parameter is omitted, a default
    configuration is used (which can be seen by running
    `swift-format dump-configuration`).

*   `--ignore-unparsable-files`: If this option is specified and a source file
    contains syntax errors or can otherwise not be parsed successfully by the
    Swift syntax parser, it will be ignored (no diagnostics will be emitted
    and it will not be formatted). Without this option, an error will be
    emitted for any unparsable files.

*   `-p/--parallel`: Process files in parallel, simultaneously across
    multiple cores.

*   `-r/--recursive`: If specified, then the tool will process `.swift` source
    files in any directories listed on the command line and their descendants.
    Without this flag, it is an error to list a directory on the command line.

### Viewing the Default Configuration

```sh
swift-format dump-configuration
```

The `dump-configuration` subcommand dumps the default configuration in JSON
format to standard output. This can be used to simplify generating a custom
configuration, by redirecting it to a file and editing it.

### Configuring the Command Line Tool

For any source file being checked or formatted, `swift-format` looks for a
JSON-formatted file named `.swift-format` in the same directory. If one is
found, then that file is loaded to determine the tool's configuration. If the
file is not found, then it looks in the parent directory, and so on.

If there is no project specific configuration file, the
[config directories](Documentation/Configuration.md#Global-Configuration)
are checked for a `swift-format/config.json` configuration file.

If no configuration file is found, a default configuration is used. The
settings in the default configuration can be viewed by running
`swift-format dump-configuration`, which will dump it to standard
output.

If the `--configuration <file|string>` option is passed to `swift-format`,
then that configuration will be used unconditionally and the file system will
not be searched.

See [Documentation/Configuration.md](Documentation/Configuration.md) for a
description of the configuration file format and the settings that are
available.

### Miscellaneous

Running `swift-format -v` or `swift-format --version` will print version
information about `swift-format` version and then exit.

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
[`SwiftFormatter`](Sources/SwiftFormat/API/SwiftFormatter.swift) and
[`SwiftLinter`](Sources/SwiftFormat/API/SwiftLinter.swift) classes for more
information about their usage.

### Checking Out the Source Code for Development

The `main` branch is used for development. Pull requests should be created
to merge into the `main` branch; changes that are low-risk and compatible with
the latest release branch may be cherry-picked into that branch after they have
been merged into `main`.

If you are interested in developing `swift-format`, there is additional
documentation about that [here](Documentation/Development.md).

## Contributing

Contributions to Swift are welcomed and encouraged! Please see the
[Contributing to Swift guide](https://swift.org/contributing/).

Before submitting the pull request, please make sure you have [tested your
 changes](https://github.com/apple/swift/blob/main/docs/ContinuousIntegration.md)
 and that they follow the Swift project [guidelines for contributing
 code](https://swift.org/contributing/#contributing-code).

To be a truly great community, [Swift.org](https://swift.org/) needs to welcome
developers from all walks of life, with different backgrounds, and with a wide
range of experience. A diverse and friendly community will have more great
ideas, more unique perspectives, and produce more great code. We will work
diligently to make the Swift community welcoming to everyone.

To give clarity of what is expected of our members, Swift has adopted the
code of conduct defined by the Contributor Covenant. This document is used
across many open source communities, and we think it articulates our values
well. For more, see the [Code of Conduct](https://swift.org/code-of-conduct/).
