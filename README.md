# Swift Log OSLog

A [`swift-log`](https://github.com/apple/swift-log) backend implementation for Darwin `OSLog`.

## What it provides

### `OSLogHandler`

- `OSLogHandler` — a `LogHandler` that writes to the Darwin unified logging system and maps `Sensitivity` to the OSLog
  privacy model. It writes the metadata as `key=value` pairs, or as JSON objects with the `.json` metadata format.

### `SensitivityAttribute`

- `Sensitivity` — a two-case attribute (`.sensitive`, `.public`) that conforms to
  `Logger.MetadataValueAttributes.Attribute`.
- `RedactionLogHandler` — a `LogHandler` wrapper that rewrites metadata entries not tagged `.public` to
  `"<redacted>"` before forwarding.
> Check out [SLG-0004-metadata-value-attributes.md](https://github.com/apple/swift-log/blob/main/Sources/Logging/Docs.docc/Proposals/SLG-0004-metadata-value-attributes.md) to learn more about the metadata attributes in `swift-log`.

## Usage

Add dependency to the `Package.swift`:

```swift
.package(url: "https://github.com/apple/swift-log-oslog", .upToNextMinor(from: "0.1.0"))
```

```swift
.product(name: "SensitivityAttribute", package: "swift-log-oslog")
```

Then import `SensitivityAttribute` and start logging:

```swift
import Logging
import SensitivityAttribute

let redactingLogger = Logger(label: "my_app", factory: { label in
    RedactionLogHandler(
        wrapping: StreamLogHandler.standardOutput(label: label)
    )
})

redactingLogger.info("Hello, world", metadata: [
    "foo": "\("foo", sensitivity: .public)",
    "bar": "\("bar", sensitivity: .sensitive)"
])

// Outputs:
// 2026-10-01T09:41:00-0700 info my_app: bar=<redacted> foo=foo [my_app] Hello, world
```

In a development build, install `StreamLogHandler.standardOutput(label:)` directly, without wrapping it in a
`RedactionLogHandler`, to forward sensitive values unchanged.

### JSON metadata

With the `.json` metadata format, `OSLogHandler` writes the public metadata and the sensitive metadata as one JSON
object each. A program that reads the log back through `OSLogStore` gets the message and each object as separate
components and parses them with a JSON parser. See `Examples/OSLogJSONRoundTrip` for the round trip.

```swift
import Logging
import OSLogHandler
import SensitivityAttribute

let logger = Logger(label: "auth") { label in
    OSLogHandler(subsystem: "com.example.myapp", category: label, metadataFormat: .json)
}

logger.info("Login successful", metadata: [
    "user.id": "\("12345", sensitivity: .sensitive)",
    "action": "\("password", sensitivity: .public)",
])

// A reader with access to private data sees:
// Login successful public={"action":"password"} sensitive={"user.id":"12345"}
// Any other reader sees:
// Login successful public={"action":"password"} sensitive=<private>
```
