# Diagnostics

Inspect what DexcomKit is doing using the unified logging system.

## Log structure

Everything is logged under the subsystem `com.kylebshr.DexcomKit`, split into
categories:

| Category | Contents |
| --- | --- |
| `connection` | Central state, connects, disconnects, rescan scheduling |
| `discovery` | Scanning and adoption decisions |
| `messages` | Message routing, parse results, readings |
| `backfill` | Backfill buffering and delivery |
| `session` | Adoption, session establishment, session end |
| `persistence` | Store reads and writes |

Levels follow intent: `.debug` for per-event chatter, `.info` for state
transitions and lifecycle milestones, `.error` for parse/auth/connect
failures.

## Watching live

Stream logs from a connected device:

```
log stream --predicate 'subsystem == "com.kylebshr.DexcomKit"' --level debug
```

Or filter in Console.app by subsystem. To collect a window of history from
a device:

```
sudo log collect --device --last 2h
```

A healthy session cycles like this every ~5 minutes:

```
connection  State: waitingForReading → scanning
discovery   Connecting to <private> rssi -62
connection  State: scanning → connecting
connection  Connected; discovering services
connection  Services ready; awaiting authentication status
connection  State: connecting → authenticating
connection  Sensor session authenticated; subscribing to glucose
connection  State: authenticating → connected
messages    Reading at offset 300294: <private> mg/dL, state 6
connection  Disconnected (remote: true)
connection  State: connected → waitingForReading
```

## Privacy

Operational data — states, opcodes, byte counts, timings, RSSI — is logged
`.public` so logs are useful as-is. Glucose values, trend rates, sensor
names, and peripheral identifiers are `.private` (sensor names embed the
pairing code, and readings are health data); they appear as `<private>`
unless the device has a logging profile installed.

## In-app log export

Apps can retrieve DexcomKit's recent logs programmatically for a support/
diagnostics screen:

```swift
import OSLog

let store = try OSLogStore(scope: .currentProcessIdentifier)
let position = store.position(date: .now.addingTimeInterval(-3600))
let entries = try store.getEntries(at: position)
    .compactMap { $0 as? OSLogEntryLog }
    .filter { $0.subsystem == "com.kylebshr.DexcomKit" }
```

## Instruments

Connection windows are wrapped in `OSSignposter` intervals (category
`connection`), so scan-to-reading latency and connection duration are visible
in Instruments' os_signpost track.

## What can't be observed in tests

CoreBluetooth state restoration — iOS relaunching the app for a sensor
event — only happens on a physical device, so it isn't covered by CI. When
debugging restoration, watch for `Restoring N peripherals` in the
`connection` category right after launch.
