# DiagnosticsKit

In-app diagnostics: audio session state monitoring and an on-device error log with a
shareable viewer.

## Requirements

- iOS 17+ / macOS 14+
- Swift 5.9+

## Installation

```swift
.package(url: "https://github.com/sphericalwave/DiagnosticsKit.git", branch: "main")
```

## Overview

- `AudioSessionMonitor` — observes `AVAudioSession` route/interruption changes
- `AudioSessionSnapshot` — a point-in-time snapshot of the audio session state
- `ErrorLog` — `ObservableObject` ring buffer of app errors
- `DiagnosticEntry` — a single logged entry (`Identifiable`, `Codable`)
- `DiagnosticsView` — SwiftUI viewer for the error log, with copy-to-pasteboard support

## Dependencies

None.
