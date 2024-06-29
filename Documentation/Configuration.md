# `swift-format` Configuration

`swift-format` allows users to configure a subset of its behavior, both when
used as a command line tool or as an API.

## Command Line Configuration

A `.swift-format` configuration file is a JSON file with the following
top-level keys and values:

*   `version` _(number)_: The version of the configuration file. For now, this
    should always be `1`.

*   `lineLength` _(number)_: The maximum allowed length of a line, in
    characters.

*   `indentation` _(object)_: The kind and amount of whitespace that should be
    added when indenting one level. The object value of this property should
    have **exactly one of the following properties:**

    *   `spaces` _(number)_: One level of indentation is the given number of
        spaces.
    *   `tabs` _(number)_: One level of indentation is the given number of
        tabs.

*   `tabWidth` _(number)_: The number of spaces that should be considered
    equivalent to one tab character. This is used during line length
    calculations when tabs are used for indentation.

*   `maximumBlankLines` _(number)_: The maximum number of consecutive blank
    lines that are allowed to be present in a source file. Any number larger
    than this will be collapsed down to the maximum.

*   `respectsExistingLineBreaks` _(boolean)_: Indicates whether or not existing
    line breaks in the source code should be honored (if they are valid
    according to the style guidelines being enforced). If this settings is
    `false`, then the formatter will be more "opinionated" by only inserting
    line breaks where absolutely necessary and removing any others, effectively
    canonicalizing the output.

*   `lineBreakBeforeControlFlowKeywords` _(boolean)_: Determines the
    line-breaking behavior for control flow keywords that follow a closing
    brace, like `else` and `catch`. If true, a line break will be added before
    the keyword, forcing it onto its own line. If false (the default), the
    keyword will be placed after the closing brace (separated by a space).

*   `lineBreakBeforeEachArgument` _(boolean)_: Determines the line-breaking
    behavior for generic arguments and function arguments when a declaration is
    wrapped onto multiple lines. If true, a line break will be added before each
    argument, forcing the entire argument list to be laid out vertically.
    If false (the default), arguments will be laid out horizontally first, with
    line breaks only being fired when the line length would be exceeded.
    
*   `lineBreakBeforeEachGenericRequirement` _(boolean)_:  Determines the 
    line-breaking behavior for generic requirements when the requirements list 
    is wrapped onto multiple lines. If true, a line break will be added before each
    requirement, forcing the entire requirements list to be laid out vertically. If false
    (the default), requirements will be laid out horizontally first, with line breaks 
    only being fired when the line length would be exceeded.

*   `prioritizeKeepingFunctionOutputTogether` _(boolean)_: Determines if 
    function-like declaration outputs should be prioritized to be together with the
    function signature right (closing) parenthesis. If false (the default), function 
    output (i.e. throws, return type) is not prioritized to be together with the 
    signature's right parenthesis, and when the line length would be exceeded,
    a line break will be fired after the function signature first, indenting the 
    declaration output one additional level. If true, A line break will be fired 
    further up in the function's declaration (e.g. generic parameters, 
    parameters) before breaking on the function's output.  

*   `indentConditionalCompilationBlocks` _(boolean)_: Determines if
    conditional compilation blocks are indented. If this setting is `false` the body
    of `#if`, `#elseif`, and `#else` is not indented. Defaults to `true`.

*  `lineBreakAroundMultilineExpressionChainComponents` _(boolean)_:  Determines whether
   line breaks should be forced before and after multiline components of dot-chained
   expressions, such as function calls and subscripts chained together through member
   access (i.e. "." expressions). When any component is multiline and this option is
   true, a line break is forced before the "." of the component and after the component's
   closing delimiter (i.e. right paren, right bracket, right brace, etc.).

*  `spacesAroundRangeFormationOperators` _(boolean)_: Determines whether whitespace should be forced
   before and after the range formation operators `...` and `..<`.

*  `multiElementCollectionTrailingCommas` _(boolean)_: Determines whether multi-element collection literals should have trailing commas.
    Defaults to `true`.

> TODO: Add support for enabling/disabling specific syntax transformations in
> the pipeline.

### Example

An example `.swift-format` configuration file is shown below.

```json
{
    "version": 1,
    "lineLength": 100,
    "indentation": {
        "spaces": 2
    },
    "maximumBlankLines": 1,
    "respectsExistingLineBreaks": true,
    "lineBreakBeforeControlFlowKeywords": true,
    "lineBreakBeforeEachArgument": true
}
```

## Linter and Formatter Rules Configuration

In the `rules` block of `.swift-format`, you can specify which rules to apply
when linting and formatting your project. Read the
[rules documentation](RuleDocumentation.md) to see the list of all
supported linter and formatter rules, and their overview.

You can also run this command to see the list of rules in the default
`swift-format` configuration:

    $ swift-format dump-configuration

## Global Configuration

If no `.swift-format` can be found for the current project/file, the configuration directories
are searched for a `swift-format/config.json` file. While the filename is different,the
configuration format stays the same.

Locations that are searched, in this order:

- `~/Library/Application Support/swift-format/config.json`
- `$XDG_CONFIG_HOME/swift-format/config.json`
- `~/.config/swift-format/config.json`

## API Configuration

The `SwiftConfiguration` module contains a `Configuration` type that is
equivalent to the JSON structure described above. (In fact, `Configuration`
conforms to `Codable` and is how the JSON form is read from and written to
disk.)

The `SwiftFormatter` and `SwiftLinter` APIs in the `SwiftFormat` module take a
mandatory `Configuration` argument that specifies how the formatter should
behave when acting upon source code or syntax trees.

The default initializer for `Configuration` creates a value equivalent to the
default configuration that would be printed by invoking
`swift-format dump-configuration`. API users can also provide their own
configuration by modifying this value or loading it from another source using
Swift's `Codable` APIs.
