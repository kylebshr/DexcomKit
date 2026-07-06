# Getting Started

Set up your app to follow a G7 sensor and keep readings flowing in the
background.

## Prerequisites

The sensor must already be running a session with the official Dexcom app
(or a Dexcom receiver) — DexcomKit follows that session; it can't start one.

## Configure your app target

Add to your `Info.plist`:

- `NSBluetoothAlwaysUsageDescription` — required for any Bluetooth use.
- `UIBackgroundModes` containing `bluetooth-central` — required for readings
  to arrive while your app is in the background.

For readings to survive app termination, pass a stable
``G7Configuration/restoreIdentifier`` so CoreBluetooth state restoration can
relaunch your app for sensor events:

```swift
let configuration = G7Configuration(
    restoreIdentifier: "com.example.myapp.dexcomkit"
)
let monitor = G7SensorMonitor(configuration: configuration)
```

Create the monitor and call ``G7SensorMonitor/start()`` early in app launch —
restoration events are delivered shortly after launch, and the monitor must
exist to receive them.

> Note: If the user force-quits your app, iOS will not relaunch it for
> Bluetooth events. This is system behavior; readings resume the next time
> the user opens the app.

## Find and follow a sensor

With the default ``SensorSelection/automatic`` selection, the monitor adopts
the first G7-family sensor that proves it has an authenticated session —
a neighbor's sensor never authenticates against your phone, so it is never
adopted. If several sensors in your household could be in range, target one
explicitly with the last two characters of its pairing code:

```swift
let configuration = G7Configuration(selection: .nameSuffix("8T"))
```

Once a sensor delivers its first authenticated reading, its identity is
persisted through the configured ``DexcomKitStore`` and the monitor reconnects
to it across app launches. Call ``G7SensorMonitor/forgetSensor()`` to clear it.

## Consume readings

Two complementary surfaces:

**Snapshot state** — observable properties, ideal for SwiftUI:

```swift
struct GlucoseView: View {
    let monitor: G7SensorMonitor

    var body: some View {
        VStack {
            Text(monitor.latestReading?.glucose.map(String.init) ?? "—")
            Text(String(describing: monitor.connectionState))
        }
    }
}
```

**Event streams** — every consumer gets an independent stream:

```swift
Task {
    for await event in monitor.events() {
        switch event {
        case .reading(let reading):
            updateLiveActivity(with: reading)
        case .backfill(let readings):
            store(readings)  // gaps recovered after reconnection
        case .sessionEnded(let reason):
            notifySensorNeedsReplacement(reason)
        default:
            break
        }
    }
}
```

> Note: Readings are deduplicated within a run, but after an app relaunch
> the sensor's current reading can be delivered again. If you persist
> readings, dedupe by ``GlucoseReading/id`` — it is stable for a given
> reading across launches.

## Live Activities

Drive Live Activity updates from ``G7SensorMonitor/readings()`` — each
background wake for a sensor connection delivers the new reading, which you
push into your `Activity`. Use an App Group store so widget extensions can
read the followed sensor's session:

```swift
let configuration = G7Configuration(
    store: UserDefaultsStore(suiteName: "group.com.example.myapp"),
    restoreIdentifier: "com.example.myapp.dexcomkit"
)
```

## Trusting a reading

Check ``GlucoseReading/isUsableForTreatment`` before acting on a value — it
is `true` only when the sensor reports the ``AlgorithmState/State/ok``
algorithm state, a glucose value is present, and the value isn't marked
display-only. During warmup (about 27 minutes after activation) readings
arrive without usable values.
