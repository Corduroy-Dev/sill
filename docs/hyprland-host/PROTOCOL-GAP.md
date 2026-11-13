# Protocol gap: upstream Swift against the Rust port

What the App Store app speaks, what PR #128's `sill-protocol` and `sill-host-core` speak, and
what the Hyprland beta does about each difference.

- **Specification:** `Sources/StreamProtocol/` at upstream commit `bf69067` (Sill 0.6.2), the
  commit this branch forks from. The root `CLAUDE.md`, "Compatibility floor", states the rules.
- **Rust port:** `hosts/` at PR #128's head `173843b`, written against upstream `5c323e6`
  (2026-10-15). Since then upstream changed 11 files in `Sources/StreamProtocol`
  (+1014 −48 lines).
- **Method:** read from the code on 2026-11-13, not from names. Paths are relative to the repo;
  `hosts/…` paths exist once M1 imports the workspace. Nothing here was run against a device.

**Beta column.** *required*: M2 must close it. *optional*: a should-have, closed only if the
must-haves are solid. *decline*: not built; the last column says how the host says so.
*have*: already in the Rust port and correct.

## 1. Summary

- The Rust port has kinds 0 to 28, its header is byte-exact, and every struct it has matches
  Swift's field names, optionality and raw values.
- It lacks kinds **32, 43, 44 and 47** and every optional field upstream added after
  2026-10-15. Kind 32 and `WindowList.clipboard` already existed at the port's base: the port
  left them out. The report's "clipboard arrived after it was written" is wrong.
- The beta must add kind 44, the locked window list, the viewport bounds, and decoding of the
  new optional fields. Clipboard (32), gestures (28, already a type, ignored by core) and key
  repeat are optional. Audio (43), display stops (47), menus (24, 25, 27), the cable and
  Direct Wireless are declined.
- Declining almost never needs a message. The app shows or hides each control from a field
  the host leaves out.

## 2. Header and limits

| Bytes | Field | Encoding |
|---|---|---|
| 0 | kind | UInt8 |
| 1–8 | timestamp | Double bit pattern, big endian: the host's clock, seconds since 1970 |
| 9 | isKeyframe | true only when the byte is 1 |
| 10–13 | payload length | UInt32, big endian |

`Sources/StreamProtocol/StreamMessage.swift:142-156`; `hosts/sill-protocol/src/wire.rs:145-165`
matches. Rust keeps an unknown kind's raw byte (`Unknown(u8)`); Swift maps it to 255.

| Cap | Value | Swift | Rust |
|---|---|---|---|
| A device's payload | 1 MiB | `StreamMessage.swift:119-125` | constant in `wire.rs:12-18`, enforced in `sill-host-core/src/server.rs:415` |
| A pairing payload | 4096 bytes | same | `sill-host-core/src/door.rs:357` |
| A frame | 32 MiB | same | constant only |
| Other host → device | 4 MiB | same | constant only |
| Kind 43 format / packets | 4096 / 16384 bytes | `Audio.swift:142-143` | absent (declined) |

## 3. Every kind

H→D is host to device, D→H device to host.

| # | Name | Dir | Payload | Gate | Rust | Beta | To close or decline |
|---|---|---|---|---|---|---|---|
| 0 | parameterSets | H→D | binary: NAL length size, count, then length-prefixed sets | before every keyframe | yes | have | Keep sending it before each keyframe and to a device that joins |
| 1 | frame | H→D | one HEVC access unit, 4-byte length-prefixed NALs | | yes | have | |
| 2 | windowList | H→D | JSON `WindowList` | on connect and on change | partial | **required** | Add the fields in section 4 |
| 3 | thumbnail | H→D | window id (u32 BE) + JPEG | not while locked | yes | optional | Backend may return none; M3 adds it if capture is cheap |
| 4 | appIcon | H→D | id length + app id + PNG | not while locked | yes | optional | Reuse the X11 crate's `.desktop` and icon lookup |
| 5 | appList | H→D | JSON `[AppInfo]` | not while locked | yes | optional | An empty list is valid: the app then offers nothing to launch |
| 6 | selectSource | D→H | JSON `StreamSource` | | yes | have | |
| 7 | launchApp | D→H | JSON `LaunchApp` | only apps the host listed | yes | optional | Goes with kind 5 |
| 8 | input | D→H | JSON `InputEvent` | hardware-keyboard characters as keys only if `keyRepeat` ≥ 1 | yes | have | |
| 9 | viewport | D→H | JSON `Viewport` | | yes | **required** | Add `ViewportBounds`: each side 1 to 16384, scale absent or 0.25 to 4, else refuse the whole message and keep the last viewport (`Viewport.swift:45-63`) |
| 10 | ping | D→H | 8 bytes (16 for a clipboard receipt) | | yes | have | Core echoes any payload, which the receipt needs |
| 11 | pong | H→D | the ping's payload | | yes | have | |
| 12 | clientStats | D→H | JSON `ClientStats` | once a second | partial | have | Unknown keys are ignored; add the two audio fields for the log only |
| 13 | tick | H→D | empty | every 30 ms while streaming or 3 s after input | yes | have | |
| 14 | cursorShape | H→D | 4 × Float32 BE (hot x, hot y, w, h) + PNG | not while locked | yes | have | Sizes in points, not pixels: afds/sill-linux drew it twice too big on an iPad |
| 15 | windowCommand | D→H | JSON `{id, action}`: close, minimize, fullScreen | none: the app always offers them | yes | **required** to accept | Close and full screen map to Hyprland; minimize has no equivalent and is ignored. Rust takes any `action` string where Swift fails the decode: reject unknown ones |
| 16 | hostSettings | H→D | JSON `HostSettingsState` | within 2 s of the first window list, one per connection | partial | **required** | Add the fields in section 4; see section 5 for the values that decline |
| 17 | changeSettings | D→H | JSON `HostSettingsChange` | at most 4 a second | partial | have | A change of `sendAudio` alone counts as empty: correct while audio is declined |
| 18 | macInfo | H→D | JSON `SignedMacInfo` | from a host with an identity | yes | have | The device checks the signature against the TLS key of this connection |
| 19 | pairRequest | D→H | JSON `PairRequest` | the one message of a `sill-pair/1` connection | yes | have | A `cable` claim is treated as a plain ask; never answer `method: "cable"` |
| 20 | pairResult | H→D | JSON `PairResult`, then close | | yes | have | |
| 21 | pairingWanted | D→H | empty | home door, once per 30 s | kind only | optional | Opens the pairing window from a session at an open door |
| 22 | goodbye | H→D | JSON `Goodbye` | | yes | have | |
| 23 | hello | D→H | JSON `Hello` | first message of a session | partial | **required** | Add `audio`, `offConsoleView` (decode only) |
| 24 | macMenu | H→D | JSON `MacMenu` | only to a subscriber | yes | **decline** | Send none. The Menus button shows only for a non-empty top level or a `note` (`iOSClient/MacMenuState.swift:150`) |
| 25 | pressMenuItem | D→H | JSON | | yes | **decline** | Ignore; none arrive without kind 24 |
| 26 | macPointer | H→D | JSON `MacPointer` | not to the device moving it; on change | yes | have | |
| 27 | fetchMenu | D→H | JSON | | yes | **decline** | Ignore |
| 28 | gesture | D→H | JSON `TrackpadGesture` | only to a host whose list says `gestures` ≥ 1 | type only, core ignores it | optional | Decline by leaving `gestures` out, as core does now |
| 32 | clipboard | both | JSON `{text?, image?, stop?}` | D→H only if the list says `clipboard` ≥ 1; H→D only to a subscriber; text ≤ 256 KB | **no** | optional | Decline by leaving `clipboard` out |
| 43 | audio | H→D | type byte + JSON format, or binary packets | only to a device whose hello lists a codec, while Send Audio is on | **no** | **decline** | Never send it; `settings.sendAudio` absent in kind 16 |
| 44 | keyframeRequest | D→H | empty | at most one a second per connection | **no** | **required** | New kind; route to `Stream::request_keyframe`, rate limited, only while something streams |
| 47 | nextDisplay | D→H | empty | only to a host whose list says `desktopDisplays` ≥ 2 | **no** | **decline** | Leave `desktopDisplays` out; the Desktop is one monitor |

Kinds 29 to 31, 33 to 42, 45 and 46 are not in upstream's enum. An unknown kind is read and
dropped on both sides (`hosts/sill-host-core/src/server.rs:463`), which is upstream's rule.

## 4. Fields missing from structs the port has

All are optional in Swift.

| Struct | Missing in Rust | Beta |
|---|---|---|
| `WindowList` | `clipboard: Int?` | optional (set to 1 with kind 32) |
| `WindowList` | `keyRepeat: Int?` | optional (set to 1 once a held key is seen to repeat in a client) |
| `WindowList` | `locked: Bool?`, `offConsole: Bool?` | **required**: `locked` true with no windows while the session is locked; `offConsole` never |
| `WindowList` | `offConsoleView: Bool?`, `desktopDisplays: Int?`, `desktopDisplay: Int?`, `desktopDisplayNames: [String]?` | decline: never set |
| `Hello` | `audio: [String]?`, `offConsoleView: Int?` | decode and ignore |
| `StreamSettings` | `sendAudio: Bool?` | decline: absent |
| `HostSettingsState` | `audioNote: String?`, `sessionPaired: Bool?` | `sessionPaired` to port from `Sources/SillHost`; `audioNote` absent |
| `HostSettingsChange` | `sendAudio: Bool?` | decode and ignore |
| `ClientStats` | `audioBehindMs: Int?`, `audioLate: Int?` | decode and ignore |

Missing types: `Clipboard`, `AudioFormat`, `AudioPackets`, `AudioMessage` (only the first is
wanted). Everything else was compared field by field and matches: `WindowInfo`, `AppInfo`,
`StreamSource`, every `InputEvent` case, `Viewport`, `RunningStream`, `AwayQuality`,
`LinkReport`, `MacInfo`, `MacAddress`, `SignedMacInfo`, `PairRequest`, `PairResult`, `Goodbye`,
`MacMenu` and its items, `MacPointer`, `TrackpadGesture`, `ParameterSets`, `ImageBlob`,
`CursorShapeBlob`.

**JSON encoding.** Swift uses a bare `JSONEncoder` and `JSONDecoder`
(`Sources/StreamProtocol/Switcher.swift:233-238`): no sorted keys, absent optionals left out,
`Data` as base64, no dates on the wire. The Rust side writes whole doubles as integers to match
a payload recorded from `SillHost` (`hosts/sill-protocol/src/messages.rs:17-28`). Not confirmed:
Foundation escapes `/` as `\/` and serde does not, which matters only where bytes are compared.

## 5. What a host must do that no struct says

Each line was read in the Swift host or the iOS client.

**Discovery**
- Service type `_sill._tcp`; the instance name is the machine's name.
- TXT keys are `r` and `p` only (`Sources/SillHost/HostIdentity.swift:92-97`).
- `p` is `"1"` with pairing required, `"0"` open. **With no `p` a Release app shows the row as
  "Update Sill" and dials nothing** (`iOSClient/DiscoveryPolicy.swift:1051`, `:1085`).
- `r` is base64url of a 6-byte nonce and the first 6 bytes of
  `HMAC-SHA256(recognitionKey, "sill-tag-v1" ‖ nonce)`: 16 characters, new at every
  registration (`Sources/StreamProtocol/Pairing.swift:138-175`).
- The home port is ephemeral upstream and read from the SRV record; the remote door's default
  is 7455.

**TLS**
- TLS 1.3 only, no tickets, no resumption. The server offers `sill/1` and `sill-pair/1` and
  requires a client certificate; the client sends SNI `sill`.
- Each side presents a self-signed P-256 certificate rebuilt at launch. Trust is the SHA-256
  of the SubjectPublicKeyInfo alone.
- An unpaired key asking for `sill/1` is refused **in the handshake** while pairing is required
  (`Sources/SillHost/DoorPolicy.swift:69-79`), and judged again at ready. afds/sill-linux
  instead completes the handshake and sends goodbye `pairingRequired`; the Swift host is the
  specification, so the beta follows it.

**Pairing** (`sill-pair/1`): one kind 19 within 4 s, one kind 20, close. `v` other than 1 is
answered `closed`. Five tries, waits of 1, 2, 4, 8 s, a window of 300 s. PBKDF2-HMAC-SHA256,
600,000 rounds, off the network thread.

**Session start**
- The device's hello (23) is the first message. The device floor is `"0"`: admit at once.
- The host sends, in order: window list (2), settings (16), Mac info (18), icons (4), app
  list (5), cursor shape (14), then asks its stream for a keyframe
  (`Sources/SillHost/StreamCoordinator.swift:3603-3643`).
- **The device counts the session as up only at its first window list, within 10 s**
  (`iOSClient/RemoteDialPolicy.swift:17`). With `active` none it asks for the Desktop itself.
- `hostVersion` is left out, as `SillHost` leaves it out: no Release code path compares it,
  and a value would claim a feature set this host does not have. `protocol` is 1; `launchID`
  is new at each launch.

**Kind 16 values that decline.** `virtualDisplayAvailable: false` with `virtualDisplayNote`
until the virtual display exists; `directWireless` absent (no row); `settings.sendAudio`
absent (the switch is disabled and reads "Update Sill on ‹name›…", with no Mute row). Without
a kind 16 within 2 s the whole panel reads "Update Sill on ‹name› to change these from here".
Picks are limited to `SettingsChoices`.

**Locked session.** The list carries `locked: true`, no windows and no `clipboard`; no
thumbnail, icon, app list, pointer, cursor shape or clipboard leaves the host; the stream is a
black placeholder (`Sources/SillHost/LockPolicy.swift:296-347`, `:498-510`). Input is taken
only from a paired session.

**Liveness**
- The device pings four times a second and drops the host after max(6 s, 4 × its worst recent
  round trip) without a byte.
- The host drops a home device that has not taken a frame for 4 s, after 8 s of grace, and
  sets TCP keepalive (5 s idle, 2 s × 3).
- The app closes its connection when it goes to the background and dials again when it comes
  back: the reconnect must be cheap.

**Goodbye reasons the app knows:** `quit`, `busy`, `remoteOff`, `internetOff` (it reconnects);
`removed`, `pairingRequired` (it does not); `update` and anything else follow `reconnect`, and
the app shows the host's `message` word for word.

## 6. What the app will say that the host cannot change

The unmodified app words every missing feature as an old Mac. On a Hyprland host a person will
read "Update Sill on ‹name›" under Send Audio, and under Three-Finger Gestures until `gestures`
is set. `BETA-TEST.md` must say these lines are expected.

## 7. Test evidence this document still needs

- **Fixtures.** There is no Swift toolchain on Linux, so M2's fixtures are built by hand from
  the Swift definitions and checked against `Scripts/sillclient.py`, which is an independent
  implementation in Python. A payload recorded from a real Sill for Mac would be stronger
  (`sillclient.py --dump`): see `DECISIONS.md`, "Needs Mark".
- **Kind 32.** `sillclient.py --clipboard --copy=TEXT@T` drives it; no device has confirmed a
  third-party host's clipboard (afds/sill-linux tested with Sill 0.5.1, which has none).
- **Input from the test client.** `sillclient.py` sends input only to a listener whose
  arguments include `--synthetic`, found with `/usr/sbin/lsof` (`Scripts/sillclient.py:263-275`).
  That holds for T1 on Arch against `sill-host-synthetic --synthetic`. It can never hold for
  T3, which therefore needs the Rust test client `PLAN.md` describes.
