# ``DexcomKit``

Connect directly to a Dexcom G7 sensor and stream glucose readings, alongside
the official Dexcom app on the same phone.

## Overview

DexcomKit is a *follower*: it connects to the G7 as a second Bluetooth
listener next to the official Dexcom app, which remains the sensor's primary
controller. The sensor must be activated and paired with the official app (or
a Dexcom receiver) first — DexcomKit never pairs, never bonds, and never
shows a pairing dialog. It simply listens, decodes, and delivers.

The G7 advertises roughly every 5 minutes when it has a new reading, accepts
a connection for a few seconds while it delivers data, then disconnects
itself. DexcomKit rides this cycle: scan, connect, verify the sensor reports
an authenticated session, subscribe, receive, and rescan after the sensor
hangs up. ``G7ConnectionState/waitingForReading`` is therefore the *normal*
resting state of a healthy session.

```swift
import DexcomKit

let monitor = G7SensorMonitor()
try monitor.start()

// Snapshot state for SwiftUI / Live Activities:
// monitor.connectionState, monitor.latestReading, monitor.session

// Push delivery for processing every reading:
Task {
    for await reading in monitor.readings() {
        guard let glucose = reading.glucose else { continue }
        print("\(glucose) mg/dL \(reading.trendArrow.map(String.init(describing:)) ?? "")")
    }
}
```

> Important: DexcomKit is not a medical device and is not affiliated with
> Dexcom. Never make treatment decisions based on data from this library;
> use the official Dexcom app for therapy.

## Topics

### Essentials

- <doc:GettingStarted>
- ``G7SensorMonitor``
- ``G7Configuration``
- ``SensorSelection``

### Readings and sessions

- ``GlucoseReading``
- ``TrendArrow``
- ``AlgorithmState``
- ``SensorSession``

### Events and state

- ``G7Event``
- ``G7ConnectionState``
- ``BluetoothUnavailableReason``
- ``SessionEndReason``
- ``DexcomError``

### Persistence

- ``DexcomKitStore``
- ``UserDefaultsStore``

### Reference

- <doc:G7Protocol>
- <doc:Diagnostics>
