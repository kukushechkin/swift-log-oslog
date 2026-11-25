# ``OSLogHandler``

A sensitivity-aware log handler for the Darwin unified logging system.

## Overview

The OSLogHandler is a sensitivity-aware log handler for the Darwin unified logging system that maps
`Sensitivity` values to the OSLog privacy model.

## Usage

The following code creates an `OSLogHandler` and presents a simple logging example in order to show different automatic redaction, based on `debug` or `release` builds:

```swift
import Logging
import OSLogHandler
import SensitivityAttribute

let logger = Logger(label: "auth") { label in
    OSLogHandler(subsystem: "com.example.myapp", category: label)
}

let userId = "12345"
logger.info("Login successful", metadata: [
    "user.id": "\(userId, sensitivity: .sensitive)",
    "action": "\("password", sensitivity: .public)",
])
```

Production logs (Console.app, non-debug builds):

```txt
Login successful action=password <private>
```

Debug builds (Xcode attached, or `log stream --level debug`):

```txt
Login successful action=password user.id=12345
```

## Sensitivity behavior

- `.public` metadata: always visible.
- Everything else, including `.sensitive`, untagged values, and future cases: redacted as `<private>`.
- The message itself is always `privacy: .public`. Keep sensitive data in metadata, not the message.

## Metadata format

By default, `OSLogHandler` writes the metadata as `key=value` pairs. Pass `.json` to write the public metadata and the
sensitive metadata as one JSON object each:

```swift
let logger = Logger(label: "auth") { label in
    OSLogHandler(subsystem: "com.example.myapp", category: label, metadataFormat: .json)
}

logger.info("Login successful", metadata: [
    "user.id": "\("12345", sensitivity: .sensitive)",
    "action": "\("password", sensitivity: .public)",
])
```

Production logs (Console.app, non-debug builds) hide the sensitive object:

```txt
Login successful public={"action":"password"} sensitive=<private>
```

A reader with access to private data, such as Xcode attached to the process, sees:

```txt
Login successful public={"action":"password"} sensitive={"user.id":"12345"}
```

### Reading the log back

The format string of every entry is `%{public}s public=%{public}s sensitive=%{private}s`. An object without entries is
`{}`, so an entry always has three arguments: the message, the public object, and the sensitive object.

```swift
import Foundation
import OSLog

let store = try OSLogStore(scope: .currentProcessIdentifier)
let position = store.position(timeIntervalSinceLatestBoot: 0)
for case let entry as OSLogEntryLog in try store.getEntries(at: position) {
    let arguments = entry.components.filter { !$0.placeholder.isEmpty }
    guard arguments.count == 3 else { continue }
    let message = arguments[0].argumentStringValue
    // OSLog cuts an argument that does not fit, and the argument then has no string value.
    let publicObject = try arguments[1].argumentStringValue.map { try JSONSerialization.jsonObject(with: Data($0.utf8)) }
    let sensitiveText = arguments[2].argumentStringValue  // A JSON object, or `<private>`.
}
```

Each object is JSON, so a reader can also decode it into a `Decodable` type with `JSONDecoder`. The
`Examples/OSLogJSONRoundTrip` package in the repository shows the whole round trip.

### What to know

- Every leaf value is a JSON string. A `.dictionary` becomes an object and an `.array` becomes an array. A reader cannot
  tell the number `5` from the string `"5"`.
- OSLog redacts the sensitive object for a reader without access to private data. Such a reader sees `<private>`
  whether or not the object is empty. A program that reads its own process through `OSLogStore` may be able to read the
  sensitive object.
- `log show --style json` shows the format string and the rendered message, not the separate arguments. The
  separate arguments are available through `OSLogStore`.
- A person who reads the log in Console finds `key=value` pairs easier to read.
- OSLog limits the size of a message. See <doc:MessageSize>.

## Performance tips

- Keep the public text and the sensitive text each under 15 UTF-8 bytes to avoid `String` allocations. The `.json`
  format adds quotes and braces, so its text reaches that size sooner.
- Construct the metadata dict inline in the log call, so a disabled level skips the construction.

## Topics

### Creating a handler

- ``OSLogHandler/init(subsystem:category:metadataFormat:)``
- ``OSLogHandler/MetadataFormat``

### Message size

- <doc:MessageSize>

### Contributing

- <doc:Proposals>
