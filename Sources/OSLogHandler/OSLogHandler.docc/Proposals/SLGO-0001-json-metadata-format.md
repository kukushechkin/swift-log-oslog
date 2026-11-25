# SLGO-0001: JSON metadata format for `OSLogHandler`

Write the metadata of each log call as JSON objects that a program can parse.

## Overview

- Proposal: SLGO-0001
- Author(s): [Vladimir Kukushkin](https://github.com/kukushechkin)
- Status: **Awaiting Review**
- Issue: [apple/swift-log-oslog#TBD](https://github.com/apple/swift-log-oslog/issues)
- Implementation:
  - [apple/swift-log-oslog#TBD](https://github.com/apple/swift-log-oslog/pulls)
- Related links:
  - [Lightweight proposals process description](https://github.com/apple/swift-log-oslog/blob/main/Sources/OSLogHandler/OSLogHandler.docc/Proposals/Proposals.md)

### Introduction

`OSLogHandler` gets a metadata format option. The new `.json` format writes the public and the sensitive metadata of a
log call as JSON objects and never makes a sensitive value public.

### Motivation

Programs can read the unified log back with `OSLogStore`. An app can attach its recent logs to a bug report, a test can
assert on what the code under test logged, and a tool on macOS can read other processes or a logarchive. An entry that
`OSLogStore` returns exposes each argument of the log message separately, as a component. `OSLogHandler` writes up to
three arguments: the message, the public metadata, and the sensitive metadata. It leaves out a metadata argument
without entries. It writes the metadata as `key=value` pairs, with each value as it is:

```swift
logger.info("Upload failed", metadata: [
    "reason": "\("disk full\nretry later", sensitivity: .public)",
    "path": "\("/Users/a b/report.txt", sensitivity: .sensitive)",
])
```

```txt
Upload failed reason=disk full
retry later path=/Users/a b/report.txt
```

The first pair is the public argument and the second pair is the sensitive argument. A reader cannot tell where the
value of `reason` ends, and a tool that reads line by line sees two lines.

Quoting and escaping the values would fix this example. The result would be a format that only this package defines,
with no specification, no parser in Foundation, and no typed decoding, so a reader would match text or write its own
parser. JSON has all three.

### Proposed solution

Add a `metadataFormat` configuration to `OSLogHandler`:

```swift
let logger = Logger(label: "upload") { label in
    OSLogHandler(subsystem: "com.example.myapp", category: label, metadataFormat: .json)
}
```

The `logger.info` call from the Motivation then logs one line:

```txt
Upload failed public={"reason":"disk full\nretry later"} sensitive={"path":"/Users/a b/report.txt"}
```

### Detailed design

````swift
extension OSLogHandler {
    /// The text format of the metadata in a log message.
    @nonexhaustive
    public enum MetadataFormat: Sendable {
        /// Writes `key=value` pairs. This is the default.
        case keyValue

        /// Writes the public and the sensitive metadata as one JSON object each. An object without entries is `{}`.
        ///
        /// For example, `Upload failed public={"reason":"disk full"} sensitive=<private>`. A container is public only
        /// when every value inside it is tagged ``Sensitivity/public``. A container without values is sensitive.
        case json
    }

    /// Creates an OSLog handler with the specified subsystem, category, and metadata format.
    ///
    /// - Parameters:
    ///   - subsystem: Reverse-DNS identifier for the subsystem, such as `"com.example.myapp"`.
    ///   - category: Category for filtering in Console.app or with `log`.
    ///   - metadataFormat: The text format of the metadata in a log message.
    ///     The default is ``MetadataFormat/keyValue``.
    public init(subsystem: String, category: String, metadataFormat: MetadataFormat = .keyValue)
}
````

A log call with the `.json` format always has three arguments: the message, the public object, and the sensitive object.
OSLog replaces the sensitive object with `<private>` for a reader without access to private data, also when the object is
`{}`. Every leaf value is a JSON string, so a reader cannot tell the number `5` from the string `"5"`.

### API stability

- `MetadataFormat` is new. The default output does not change. `Sensitivity` and `RedactionLogHandler` do not change.
- `init(subsystem:category:)` becomes `init(subsystem:category:metadataFormat:)` with a default value. Calls with two
  arguments compile. A reference to the old initializer by name, such as `OSLogHandler.init(subsystem:category:)`, does
  not compile. The package is not yet API stable.
- The layout of `OSLogHandler` changes. No client source breaks, and the package does not use library evolution.
- `MetadataFormat` is `@nonexhaustive`, as `Sensitivity` is, so a later case is not a source break.
- The labels, the rule for containers, and the `{}` for an object without entries are part of the `.json` format.
- The package has no `@_exported import`, and this proposal adds none.

### Future directions

- Custom format support.

### Alternatives considered

- Escaped and quoted `key=value`, or logfmt. Logfmt has shorter lines and is readable in Console. Logfmt is a convention
  without a specification, and Foundation has no parser for it. Escaping `.keyValue` itself would also change the
  default output.
- Format the whole log event as one JSON object, in the handler or by hand in the message. OSLog redacts a whole argument
  or none of it, so one argument cannot keep only the sensitive part private. Nesting the sensitive part as an escaped
  string works, but a reader then parses it twice.
- Always write metadata as JSON. It changes the default output for every user, including people who read the log in
  Console.
- A second handler type, such as `OSLogJSONHandler`, in this package or in a separate package. It differs from
  `OSLogHandler` only by the format, and it adds a type, a product, and a documentation catalog for each format. A
  separate package would have to duplicate the metadata handling of `OSLogHandler` or make it public API.
- A wrapper handler in front of `OSLogHandler`, or other middleware that transforms the metadata, for example a generic
  handler that maps it with closures. `OSLogHandler` caches the text of the metadata that a logger sets. A wrapper passes
  the metadata on as a dictionary, so `OSLogHandler` cannot use that cache and formats the metadata again on every log
  call. A wrapper that passes text already split by privacy avoids this, but it needs a new public protocol.
