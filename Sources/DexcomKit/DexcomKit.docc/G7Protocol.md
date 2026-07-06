# The G7 BLE Protocol

The wire protocol DexcomKit implements, as reverse-engineered by the
LoopKit/G7SensorKit and xDrip communities.

## The follower model

The G7 is a disposable sensor+transmitter that acts as a BLE peripheral and
supports multiple simultaneous connections (phone, receiver, pump). Its
real-time and backfill glucose streams are not encrypted, so a secondary
listener can decode them without holding the sensor's pairing key.

Authentication (an EC-J-PAKE handshake using the pairing code) is performed
once, by the official Dexcom app or receiver, when the sensor is activated.
DexcomKit never performs this handshake. It connects with no options — so no
iOS pairing dialog can appear — subscribes to the authentication
characteristic, and waits for the sensor to report `authenticated && bonded`
before subscribing to glucose data.

## Discovery

| | |
| --- | --- |
| Advertised service | `FEBC` (16-bit) |
| Name prefixes | `DXCM` (G7), `DX02` (Dexcom One+) |
| Sensor discriminator | Last 2 characters of the name = tail of the pairing code |
| Cadence | Advertises ~every 5 minutes when it has a reading; connection window lasts a few seconds; the sensor disconnects itself |

The original Dexcom One (`DX01`) speaks the G6 protocol, not this one, and
is deliberately not matched.

## GATT layout

CGM service `F8083532-849E-531C-C594-30F1F86A4EA5`:

| Characteristic | UUID | Role |
| --- | --- | --- |
| Authentication | `F8083535-…` | Notifies auth status (opcode `0x05`) |
| Control | `F8083534-…` | Notifies glucose and control responses; writable |
| Backfill | `F8083536-…` | Notifies historical readings as 9-byte records |

Subscription order: authentication first; on an authenticated+bonded status,
control; backfill is enabled during glucose handling — matching the
G7SensorKit reference order.

## Control messages

Byte 0 of every control/auth message is the opcode. All integers are
little-endian.

| Opcode | Meaning |
| --- | --- |
| `0x05` | Authentication status: `[1]` authenticated, `[2]` bonded |
| `0x28` | Session stopped |
| `0x4E` | Real-time glucose |
| `0x52` | Extended version request (write) / response |
| `0x59` | Backfill stream finished |

### Glucose (`0x4E`, ≥19 bytes)

| Offset | Field |
| --- | --- |
| `[1]` | Status; only `0x00` is a valid reading |
| `[2..<6]` | Message timestamp, seconds since activation |
| `[6..<8]` | Sequence number |
| `[10..<12]` | Age: seconds between reading and transmission |
| `[12..<14]` | Glucose mg/dL (`0xFFFF` = none; masked with `0x0FFF`) |
| `[14]` | Algorithm state (see ``AlgorithmState``) |
| `[15]` | Trend ×10, `Int8`, mg/dL/min (`0x7F` = none) |
| `[16..<18]` | Predicted glucose (`0xFFFF` = none; masked with `0x0FFF`) |
| `[18]` | Flags; bit `0x10` = display-only value |

The reading's own timestamp is `messageTimestamp − age`, and the sensor's
activation date is derived as `now − messageTimestamp`.

### Backfill records (9 bytes each; notifications may carry several)

| Offset | Field |
| --- | --- |
| `[0..<3]` | Timestamp, seconds since activation (24-bit) |
| `[4..<6]` | Glucose mg/dL (`0xFFFF` = none; masked with `0x0FFF`) |
| `[6]` | Algorithm state |
| `[7]` | Flags; bit `0x10` = display-only |
| `[8]` | Trend ×10, `Int8` (`0x7F` = none) |

### Extended version (response to writing `[0x52]`, ≥15 bytes)

| Offset | Field |
| --- | --- |
| `[2..<6]` | Session length, seconds — **includes the grace period** |
| `[6..<8]` | Warmup length, seconds (~1620) |
| `[8..<12]` | Algorithm version |
| `[12]` | Hardware version |
| `[13..<15]` | Maximum lifetime, days |

The reported session length already contains the 12-hour grace period: a
real 10-day sensor reports 907 200 s (10.5 days) and a 15-day sensor
1 339 200 s (15.5 days). Expiration is the reported length minus the grace
period; the grace period ends when the reported length elapses.

DexcomKit requests this after the first reading of each connection until the
sensor answers, persists the response, and prefers its values over the
built-in defaults (27-minute warmup, 10-day session, 12-hour grace period).

## Connection loop

After every disconnect — normal or not — DexcomKit waits ~2 seconds and
rescans, so it's listening before the sensor's next advertisement. A sensor
that repeatedly disconnects while authentication is still pending has usually
ended its session; after three such strikes DexcomKit reports
``SessionEndReason/suspectedEnd``.

## Credits

Protocol knowledge comes from the open-source diabetes community, primarily
[LoopKit/G7SensorKit](https://github.com/LoopKit/G7SensorKit) and
[xDrip4iOS](https://github.com/JohanDegraeve/xdripswift).
