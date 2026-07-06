# DexcomKit

[![CI](https://github.com/kylebshr/DexcomKit/actions/workflows/ci.yml/badge.svg)](https://github.com/kylebshr/DexcomKit/actions/workflows/ci.yml)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)
![Platforms](https://img.shields.io/badge/platforms-iOS%2018%2B%20%7C%20macOS%2015%2B-blue)

A modern Swift package for connecting **directly to a Dexcom G7 sensor** and
streaming glucose readings — designed to run alongside the official Dexcom
app on the same phone.

> ⚠️ **Not a medical device.** DexcomKit is a community project, not
> affiliated with Dexcom. Never make treatment decisions based on data from
> this library — use the official Dexcom app for therapy.

## How it works

The G7 accepts multiple simultaneous BLE connections and doesn't encrypt its
real-time or backfill glucose streams. DexcomKit acts as a **follower**: the
official Dexcom app (or a receiver) pairs with the sensor and runs the
session; DexcomKit connects as a second listener — with no pairing, no
bonding, and no pairing dialog — waits for the sensor to report an
authenticated session, and decodes the readings.

The sensor advertises roughly every 5 minutes when it has a new reading,
stays connected for a few seconds while it delivers data (including backfill
for any gap while you were out of range), then disconnects itself. DexcomKit
rides that cycle and rescans between readings.

The protocol implementation follows the reverse engineering done by
[LoopKit/G7SensorKit](https://github.com/LoopKit/G7SensorKit) and
[xDrip4iOS](https://github.com/JohanDegraeve/xdripswift) — credit to those
communities.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/kylebshr/DexcomKit.git", branch: "main")
]
```

## Quick start

```swift
import DexcomKit

@MainActor
final class GlucoseStore {
    let monitor = G7SensorMonitor(
        configuration: G7Configuration(
            restoreIdentifier: "com.example.myapp.dexcomkit"
        )
    )

    func start() throws {
        try monitor.start()

        Task {
            for await reading in monitor.readings() {
                guard reading.isUsableForTreatment, let glucose = reading.glucose else { continue }
                print("\(glucose) mg/dL, \(reading.trendArrow?.rawValue ?? "steady"), at \(reading.date)")
            }
        }
    }
}
```

`G7SensorMonitor` is `@Observable`, so SwiftUI views can bind directly to
`monitor.connectionState`, `monitor.latestReading`, and `monitor.session` —
ideal for powering Live Activities. `events()` and `readings()` each return
an **independent stream per call**, so any number of consumers (UI, Live
Activity updater, storage, logging) can listen concurrently.

## App configuration

In your app target:

- `Info.plist`: `NSBluetoothAlwaysUsageDescription`
- `Info.plist`: `UIBackgroundModes` including `bluetooth-central`
- Pass a stable `restoreIdentifier` so iOS relaunches your app for sensor
  events after termination (force-quit excepted — that's system behavior)
- Optional: `UserDefaultsStore(suiteName:)` with an App Group so widget and
  Live Activity extensions can read the followed sensor's session

The sensor must already be running a session with the official Dexcom app.
With the default `.automatic` selection DexcomKit adopts the first sensor
that proves it has an authenticated session; use `.nameSuffix("8T")` (the
last two characters of the pairing code) to target a specific sensor.

## Logging

Everything DexcomKit does is visible in the unified log under the subsystem
`com.kylebshr.DexcomKit`:

```
log stream --predicate 'subsystem == "com.kylebshr.DexcomKit"' --level debug
```

Glucose values and sensor identifiers are `.private` by default; operational
data (states, opcodes, timings) is `.public`. See the Diagnostics article in
the documentation for the category map, a healthy-session log signature, and
in-app log export via `OSLogStore`.

## Documentation

The DocC catalog covers getting started, the full reverse-engineered G7 BLE
protocol (UUIDs, opcodes, byte layouts), and diagnostics. Build it locally:

```
xcodebuild docbuild -scheme DexcomKit -destination 'generic/platform=iOS'
```

## Development

The package is pure Swift 6 (strict concurrency) with CoreBluetooth hidden
behind a protocol seam, so the entire state machine — parsing, adoption,
backfill assembly, reconnect behavior — is unit-tested with scripted mocks
and byte-exact fixtures. `swift test` runs natively on macOS; CI covers both
macOS and the iOS simulator. State restoration and real advertisement
cadence can only be validated on a physical device.

## License

MIT — see [LICENSE](LICENSE).
