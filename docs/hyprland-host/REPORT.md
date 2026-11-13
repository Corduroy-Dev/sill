# Sill (getsill.app): architecture and Linux/Omarchy port feasibility

Research briefing, compiled 13 Nov 2026. Companion to `BRIEF.md`.

**How to use this file.** It is a briefing, not ground truth. It was written from READMEs, PR descriptions, release notes and third-party articles, not from reading the source. Where it disagrees with the code in the repository, the code wins. Items marked *unverified* were never confirmed. Addendum A at the end holds details checked directly against PR #128 on 13 Nov 2026 and supersedes the body where they differ.

---

## Summary

- **What Sill is:** a macOS menu-bar host (Swift) that streams one Mac window, or the whole desktop, as HEVC to a thin iPhone/iPad client. The client sends touch, pointer and keyboard input back. iOS is the viewing and input terminal; the computer being controlled is the Mac.
- **The useful Linux equivalent:** a Linux host that speaks Sill's protocol, so the unmodified App Store iOS app can drive a Hyprland desktop.
- **Verdict:** possible with caveats. Narrowing to Omarchy (Arch + Hyprland) makes it noticeably easier, because capture, input, window control and virtual outputs are all available through unprompted Wayland protocols and one IPC socket.
- **Code reuse:** none of the Swift code runs on Linux. It is the protocol specification. The Rust workspace in PR #128 is the best starting point for a host.
- **Must be dropped on Linux:** menu mirroring (Accessibility), USB "Wired" mode, Direct Wireless (AWDL).
- **Biggest risk:** the protocol is not a published, stable API. It is defined by Swift code under fast-moving development.

---

## Part 1. How Sill is implemented

### What it does and which platforms it runs on

- **Two apps.**
  - "Sill for Mac" lives in the menu bar. It captures a window or the whole desktop, encodes it as HEVC and sends it to the Sill app on iPhone/iPad.
  - The iOS app decodes and displays the stream, and sends back taps, clicks, momentum scrolls, an on-screen trackpad, keys, typed text and Apple Pencil input.
  - Three-finger swipes and pinches map to Mission Control, App Expose, Spaces and Show Desktop through the Mac's keyboard shortcuts.
- **Menu mirroring.** The streamed app's menus appear in the iPad's own menu bar (iPadOS 26+) and behind a Menus button. Sill for Mac reads each menu as it opens and presses the chosen item through Accessibility.
- **Requirements.** macOS 14+ and iOS/iPadOS 17+. Originally Apple silicon only; Intel support arrived with 0.6.0.
- **Releases.**
  - Since 0.5.1 both apps share one version number.
  - 0.6.0 (2 Nov 2026) added two-way clipboard, Mac audio as a beta, and Virtual Display plus Send Audio on by default.
  - 0.6.1 (11 Nov 2026) is the latest release found. A nightly channel also exists.
- **iOS distribution.** On the App Store (id6816359860), free. There is also a TestFlight public beta.
- **Transports.** Same LAN (Bonjour), USB cable ("Wired"), Direct Wireless Connection over peer-to-peer Wi-Fi (off by default), and Remote Access through your own VPN such as Tailscale, or a forwarded port. No account and no server.

### Languages, frameworks and build

- Everything upstream is Swift. The contribution rules in the repo's `CLAUDE.md` say: Swift and Apple frameworks only, no third-party dependencies, nothing that needs a server, latency before picture quality.
- **Mac host.** Built with SwiftPM (`Package.swift` at the repo root). `Scripts/make-app.sh --install --open` builds and signs `Sill.app`. `swift run -c release SillHost` runs the host from the command line; `--synthetic` streams a test pattern without Screen Recording permission.
- **iOS client.** `iOSClient/Sill.xcodeproj`, bundle ID `me.saffer.sill`.
- **Top-level layout (confirmed 13 Nov 2026):** `.github/`, `Packaging/`, `Scripts/`, `Sources/`, `Tests/`, `design/`, `docs/`, `iOSClient/`, `site/`, plus `CLAUDE.md`, `SECURITY.md`, `LICENSE`, `Package.swift`, `README.md`.
- **Tests and CI.** `Tests/checks/run-all.sh` runs the same pure checks as CI (about five minutes, no device). `docs/DEVELOPMENT.md` documents every command-line flag, the test tools and the simulator harness.
- The project is built with Claude Code; commits carry Claude co-author trailers.

### Architecture: modules and components

Names below come from PR text, not a file-tree audit. Verify against `Package.swift` and `Sources/`.

| Area | Files / types (as named in PRs) | Role |
|---|---|---|
| Targets | `Sources/SillHost`, `Sources/SillMenuBar` (signed as `me.saffer.sill.mac`), `Sources/StreamProtocol`; product `SillHost` | Host engine, menu-bar app shell, shared wire protocol |
| Session / server | `StreamServer.swift`, `StreamCoordinator.swift`, `Door`, `DoorPolicy`, `PairingWindow` | Listeners ("doors") for plain dev, TLS home and remote; session lifecycle |
| Protocol | `StreamMessage.swift` (kind table), `Compatibility.swift` (`SillProtocol.current` = 1), `RemoteTLS.swift` | Framed messages; JSON payloads shaped like Swift Codable; HEVC in hvcC framing |
| Input | `InputInjector` (`post()`, `.chord`), `KeyStrokes.virtualKeys` (82-key HID table), `KeyRepeat` | CGEvent injection |
| Menus | `MacMenu.swift` (`FetchMenu`, `PressMenuItem`) | Accessibility menu tree read and press |
| Pointer | `PointerControl`, `PointerWatch`, `PointerPresence` | Mirrors the local Mac pointer to the device |
| Virtual display | `Sources/SillHost/VirtualDisplay.swift` | Private `CGVirtualDisplay`, loaded by runtime lookup |
| Quality / links | `AwayPolicy`, `LinkJudge`, `CaptureScale`, `Viewport.swift` / `ViewportBounds` | Lower quality when away, link-quality notices, capture scale, viewport bounds |
| Misc | `DisplayWake`, `FirewallRule`, `HostSettings.swift` | Wake a sleeping display, detect the macOS firewall, settings sync (kinds 16/17) |
| Identity | `AppIdentity.swift`, `KeychainIdentityStore(accessGroup:)` | Code-signature self-identification; keys in the data-protection keychain |
| iOS client | `StreamClient` (+ extensions), `InputOverlay`, `TrackpadView`, `HardwareKeyboardPolicy.swift`, `Pen.swift`, `Reconnect` | Decode, display, gestures, Pencil, reconnect |

**Data flow (host side).**

1. Bonjour advertises `_sill._tcp`. The TXT record carries `p` (whether pairing is required) and a recognition tag.
2. The device dials. TLS 1.3 uses pinned self-signed P-256 keys, with ALPN `sill/1` for a session or `sill-pair/1` for pairing.
3. The device picks a source (kind 6).
4. ScreenCaptureKit captures it and VideoToolbox encodes HEVC, hardware first and software when the hardware encoder is busy. Frames are dropped, not queued.
5. Input comes back (kind 8) and is posted as CGEvents.
6. Settings (16/17), menus (24/25/27), pointer (26), gestures (28), clipboard (32) and keyframe requests (44) travel as further kinds.
7. Unknown kinds are skipped. This is the compatibility mechanism.

**Pairing.** A 12-digit code (Damm check digit) or QR code, PBKDF2 at 600k iterations, HMAC proofs. Over USB, pairing is automatic.

**State.** Keys and the paired-device list live in a keychain access group only Sill can read. Self-built copies fall back to the login keychain.

**Processes.** No evidence of a separate helper, XPC service or extension; it appears to be a single menu-bar process. *Unverified.*

### Apple OS dependencies and how they port

| Dependency | How it is used | Portability |
|---|---|---|
| ScreenCaptureKit + Screen Recording permission | Per-window and desktop capture | Equivalent exists on Hyprland |
| VideoToolbox HEVC | Hardware low-latency encode | VA-API / NVENC / Vulkan |
| CGEvent + Accessibility permission | Click, scroll, type, window move and resize | Virtual input protocols |
| Accessibility menu reading and pressing | Menu mirror to the iPad | **No general Wayland equivalent** |
| `CGVirtualDisplay` (private API) | A display sized to the device so a covered window keeps updating | Hyprland headless outputs are a public, better equivalent |
| Network.framework / Bonjour | Discovery and TLS | Avahi + rustls |
| Peer-to-peer Wi-Fi (AWDL) | Direct Wireless | **No practical Linux equivalent** |
| USB "Wired" (`CableLink`) | Connection and automatic pairing over the cable | Mechanism *unverified*; weak on Linux |
| Keychain access group | Protected identity storage | libsecret or a 0600 file |
| Mission Control / Spaces shortcuts | Three-finger gestures | Map to Hyprland dispatchers |

### Distribution, licensing, updates

- **License:** Apache-2.0, "Copyright 2026 Noah Saffer". Contributions are accepted under the same license. Apache-2.0 grants no trademark rights, so a derived project should not ship under the "Sill" name or logo.
- **Mac distribution:** Developer ID signed, notarized DMG/ZIP on GitHub Releases, linked from getsill.app, plus a Homebrew tap. Not sandboxed, and uses a private API, so it is not on the Mac App Store.
- **Updates:** once a day the app asks GitHub whether a newer version exists. It never downloads by itself.
- **Money:** free, no ads or tracking; optional GitHub Sponsors tips.

### Notable decisions, limits and known issues

- One stream at a time (one window or the desktop).
- Latency before quality: frames are dropped, not queued.
- Before 0.4.0, LAN, cable and Direct connections were unencrypted and unauthenticated. Pairing at home arrived with 0.4.0.
- A security-scan batch (PRs #249 to #255) fixed issues including a viewport-driven crash.
- The command-line `SillHost` opens a plain, unencrypted dev door unless `--pairing` is passed. **App Store builds of the iOS app refuse to dial a plain door.**
- While the virtual display is on, the streamed window leaves the Mac's own screen.

---

## Part 2. A Linux / Omarchy equivalent

### Goal

A Linux host for the existing iOS app. (A Linux viewer for a Mac host already exists in NateHag/Sill-Viewer and is out of scope.)

### Omarchy's stack, late 2026

- **Omarchy 4.0 "Quattro" (14 Aug 2026)** rewrote the desktop shell in Quickshell (QML). Bar, launcher, menus, notifications, OSDs, control panels, lock screen and polkit agent run as one long-running process with a plugin architecture. Waybar, Walker, Mako, SwayOSD, hyprlock, hypridle, swaybg and polkit-gnome are gone.
- **Omarchy menu (Super+Space)** is a nested command palette defined in JSONC, extensible via `~/.config/omarchy/extensions/omarchy-menu.jsonc`.
- **Packaging.** Omarchy internals are real Arch packages. An ALPM guard routes system updates through `omarchy update`.
- **Hyprland configuration** moved to Lua for Hyprland 0.56 compatibility.
- **Latest release found:** Omarchy 4.5.0 (5 Nov 2026).
- **Default terminal:** Foot.
- **Desktop portal.** A user report on Omarchy with Hyprland 0.57.0 shows xdg-desktop-portal-hyprland 1.4.1 exposing only Screenshot, ScreenCast, GlobalShortcuts and InputCapture. **There is no RemoteDesktop portal.** The upstream PR that would add one is still open.

### Capability map: macOS to Linux

| Sill capability | Generic Linux | Hyprland / Omarchy | Verdict |
|---|---|---|---|
| Desktop capture | ScreenCast portal + PipeWire | `ext-image-copy-capture-v1` or `wlr-screencopy` (dmabuf), no prompt | Clean |
| Single-window capture, even when covered | Portal window pick; GNOME needs an extension | `hyprland-toplevel-export-v1` (by `hyprctl clients` address) or ext-image-copy-capture with toplevel sources | Clean on Hyprland |
| Window list, focus, move, resize | Compositor-specific | `hyprctl clients -j`, `dispatch focuswindow`, `resizewindowpixel`, socket2 events | Clean, Hyprland-specific |
| Virtual display | Mutter virtual monitors via D-Bus; KDE varies | `hyprctl output create headless <name>` plus a monitor rule | Better than macOS |
| Input injection | RemoteDesktop portal + libei; uinput needs root or udev | `zwlr_virtual_pointer_v1` + `zwp_virtual_keyboard_v1`, no prompt | Clean on Hyprland |
| HEVC low-latency encode | VA-API (`hevc_vaapi`), NVENC, Vulkan; x265 fallback | Same | Clean; NVIDIA quirks |
| Menu mirroring | AT-SPI partial; dbusmenu only for some Qt/KDE apps | Same | **Drop** |
| Mission Control / Spaces gestures | DE-specific | `workspace e+1` / `e-1`, special workspace, overview plugin | Redesign |
| Host pointer shown on device | Cursor metadata in portal streams | Composite cursor in capture, or `hyprctl cursorpos` | Clean |
| Clipboard | `ext-data-control-v1` / wl-clipboard | Same | Clean |
| Audio (AAC-ELD) | PipeWire monitor capture + libfdk-aac | Same | Clean; check codec licensing |
| Bonjour discovery | Avahi (`_sill._tcp`) | Same | Clean |
| TLS 1.3 + pinned keys + pairing | rustls / OpenSSL | Same | Clean (already reimplemented in PR #128) |
| Keychain identity | Secret Service or a 0600 file | Same; whether Omarchy ships a keyring is *unverified* | Partial |
| Permissions | Portal dialogs | Native protocols are open to any client; Hyprland's permission rules, if enabled, must allow the binary | Easier, less safe |
| Menu-bar UI | StatusNotifierItem tray | Quickshell bar plugin + Omarchy-menu JSONC entries | Clean, Omarchy-specific |
| Remote Access over a VPN | Tailscale etc. | Same; firewall rule needed | Clean |
| USB "Wired" mode | iOS USB networking is unreliable on Linux | Same | **Drop** |
| Direct Wireless (AWDL) | OWL is experimental, root-only, takes the Wi-Fi interface | Same | **Drop** |
| Locked screen | Capture is refused on the lock screen | Quickshell lock (ext-session-lock) blocks capture | Limit; do not auto-unlock |

### Generic Linux vs. Omarchy only

- Generic Linux is a matrix of backends (X11, GNOME, KDE), each with its own prompts, window model and virtual-display story.
- Hyprland-only avoids the missing RemoteDesktop portal entirely. hypr-rdp proves the approach works.
- The tradeoff is churn and lock-in. Hyprland's config, protocols and IPC change often. Prefer `ext-*` protocols where possible so Sway and niri support stays cheap later.

### iPhone-specific Linux tooling

- The main link (Wi-Fi/LAN plus TLS) needs no Apple tooling. The iOS app only needs Bonjour and the Sill protocol.
- libimobiledevice, usbmuxd and pymobiledevice3 do not give a reliable equivalent of "Wired" mode. The iOS USB network link often does not come up on Linux, and iOS 17+ tunnels need root.
- OWL (AWDL) is not shippable.
- UxPlay and KDE Connect are not relevant.

### Existing projects

- **Sill PR #128 (Aileuxe, open, unmerged).** Rust hosts for Windows and Linux (X11). See Addendum A.
- **NateHag/Sill-Viewer.** Mainly a desktop viewer (Rust + FFmpeg). Also contains a Linux host written in Python for Ubuntu GNOME on Wayland. It streams to the App Store iOS app, with NVENC, VA-API or Vulkan encoding, a tray icon, a watchdog and auto-unlock. License *unverified*. Appears to be the project announced in Sill issue #109.
- **afds/sill-linux.** A Wayland host built around a GNOME Shell extension (GNOME 48 to 51). On other Wayland desktops it falls back to the portal and streams only the whole desktop. License *unverified*.
- **Technique references for Hyprland:** hypr-rdp (Rust; Hyprland IPC headless outputs, ext-image-copy-capture, VA-API, virtual input; on AUR) and wayvnc.

None of the three Sill hosts has a native Hyprland backend.

### Recommended stack

A Rust daemon plus Omarchy integration.

- **Core:** fork PR #128's `sill-protocol` and `sill-host-core`; add a Hyprland backend implementing the `Platform` trait.
  - Capture: ext-image-copy-capture (toplevel and output sources), with hyprland-toplevel-export as a fallback.
  - Input: virtual pointer and keyboard with xkbcommon keymaps.
  - Window control: Hyprland IPC, plus headless outputs for the virtual display.
  - Encode: FFmpeg (VA-API / NVENC / Vulkan, x265 fallback).
  - Discovery and TLS: Avahi, rustls.
  - Clipboard: data-control. Audio: PipeWire.
- **UI:** a Quickshell bar plugin (status, paired devices, pairing QR/code card) and Omarchy-menu JSONC entries.
- **Packaging:** an AUR PKGBUILD with a `systemd --user` unit. Open the firewall for the service ports and mDNS (5353/udp).
- **Effort (my judgement, not sourced):** about 3 to 6 weeks to an MVP for an experienced Rust/Wayland developer; 2 to 3 months to near-parity.

### Biggest risks and blockers

1. **Protocol compatibility.** Kinds keep being added. The App Store client requires the TLS/pairing door, and the author enforces a "compatibility floor". A host-side bug could stop it working with a new iOS release.
2. **Hyprland churn.** IPC, protocol and config changes every few months. There is an NVIDIA bug reported against Hyprland 0.54.0 where an ext-image-copy-capture SHM XRGB8888 buffer arrives in XBGR byte order, swapping red and blue.
3. **No RemoteDesktop portal.** The host depends on unprompted native protocols. That is a security posture to document.
4. **Dropped features:** menu mirroring, Wired USB, Direct Wireless, faithful Mission Control gestures.
5. **The iOS app assumes a Mac:** Command keys, the menu bar, Mac-style app tiles. Some controls will need mapping or will be meaningless.

### Unverified items

- The USB "Wired" mechanism.
- The home TCP port. One user report says it changes on each launch; a log in issue #314 shows remote access listening on 7455. Do not hard-code a home port.
- The frame-header byte layout.
- The licenses of NateHag/Sill-Viewer and afds/sill-linux.
- Omarchy's default firewall and keyring.
- Whether Sill for Mac runs any helper process.

---

## Addendum A. PR #128, checked directly on 13 Nov 2026

Source: https://github.com/Saffsanity/sill/pull/128 (open, no reviews, 3 commits, head branch `Aileuxe/sill:mac-client`).

**The PR bundles two unrelated things.** Only the second matters here.

1. *Sill Viewer*, a macOS client target added to `iOSClient/Sill.xcodeproj` with new views in `MacClient/`. Not needed.
2. *Rust hosts*, a separate Cargo workspace in `hosts/`. Commit `6d7419f`, "Rust hosts for Windows and Linux (work in progress)". A third commit merges upstream main into the branch.

**Crates in `hosts/`.**

- `sill-protocol`: the wire format.
  - The header and **kinds 0 to 28 only**. JSON shaped as Swift's Codable output, checked against payloads recorded from `SillHost`.
  - Video: ParameterSets, hvcC framing.
  - TLS 1.3 with pinned self-signed P-256 keys, ALPN `sill/1` and `sill-pair/1`, unpaired keys refused in the handshake.
  - Pairing: Damm codes, PBKDF2 600k, HMAC proofs, recognition tags, `sill://pair` links.
- `sill-host-core`: the host without an OS, behind one `Platform` trait.
  - Doors: the plain dev door and the TLS door with pairing (ask, code, link).
  - The remote door: kind 18, away quality, byte pacing.
  - Kinds 16/17 settings, pings, ticks, eviction, goodbye.
  - Kind 26 pointer and kind 14 cursor.
  - An FFmpeg-subprocess HEVC encoder (libx265, VAAPI, NVENC; never linked).
  - A synthetic backend.
- `sill-host-windows`: Windows.Graphics.Capture, Media Foundation HEVC, SendInput by scancode, Win32 windows with Alt-Tab filtering, Start Menu apps, icons, thumbnails, cursor shape, `DnsServiceRegister`, per-monitor DPI.
- `sill-host-linux` (X11): XComposite + MIT-SHM capture, XTest input, EWMH windows, `.desktop` apps, XFixes cursor, Avahi over D-Bus, a Dockerfile with Xvfb for testing.

**What the author verified.**

- `cargo test --workspace`: 116 tests pass; clippy clean.
- Core against `Scripts/sillclient.py`: plain door, TLS pairing (ask, code, link), a pinned session after a restart, refusals, settings, window picks, input placement, flood and junk handling, eviction, goodbye.
- The remote door's away quality through `sillrelay.py` at 2 Mbit/s and +150 ms.
- Core against a Network.framework client built from `StreamProtocol`'s RemoteTLS: pairing, pinning, kind 18.
- Linux in Docker (Debian 13, Xvfb, openbox): self-test 32/32; input end to end 15/15; streamed to the Mac viewer at 33 fps (1080p x265 on the container's CPU).
- Windows: cross-builds to an `.exe` for `x86_64-pc-windows-gnu`; 45 unit tests.

**What the author did not test.**

- Windows: nothing has run on Windows. `hosts/NOTES-windows.md` has a 15-step checklist.
- Linux: no real Linux desktop, no VAAPI or NVENC.
- Wayland: not built.
- **The iOS app has never been run against a PC host.**

**Open decisions recorded in the PR.**

- Pairing default: the PC hosts default to the plain door, as `SillHost` does. Release builds of the apps refuse it. A host for the App Store app must default to the TLS door with pairing.
- Keyboard mapping: Command and Control both become Ctrl; Option becomes Alt; right Option is left Alt, not AltGr.
- Resolution cap: 4096 px per side on Windows.

**Implications.**

- The protocol crate is behind upstream. Upstream has since added kinds beyond 28, including clipboard (32) and keyframe requests (44), and shipped audio in 0.6.0. The gap must be measured against `Sources/StreamProtocol` at the forked commit.
- NateHag's Python host is the only community host reported to work with the App Store iOS app. It is the best behavioural reference for anything PR #128 could not test against a real device.
- Each crate keeps a `NOTES-*.md` saying what is verified and what is not. Follow that convention.

**Related forks seen.** Valdex/sill adds "Sill for Windows", an unofficial *client* that views a Mac from a Windows PC. Not a host.

---

## Sources

Upstream

- https://github.com/Saffsanity/sill
- https://getsill.app
- https://github.com/Saffsanity/sill/pull/128 (Rust hosts)
- https://github.com/Saffsanity/sill/issues/109 (community Linux host announcement)
- https://github.com/Saffsanity/sill/pull/37 (pairing at home, TLS)
- https://github.com/Saffsanity/sill/pull/42 (keychain hardening, entitlements)
- https://github.com/Saffsanity/sill/pull/87 (VirtualDisplay on Intel)
- https://github.com/Saffsanity/sill/pull/156 (desktop full screen on a device-sized display)
- https://github.com/Saffsanity/sill/pull/262 (security integration)
- https://github.com/Saffsanity/sill/pull/285 (0.6.0 docs)
- https://github.com/Saffsanity/sill/releases (v0.4.0, v0.5.1, v0.6.0, v0.6.1, nightly)
- https://github.com/Saffsanity/homebrew-sill

Community hosts

- https://github.com/NateHag/Sill-Viewer
- https://github.com/afds/sill-linux

Hyprland and Wayland

- https://wayland.app/protocols/hyprland-toplevel-export-v1
- https://github.com/hyprwm/Hyprland/discussions/13332
- https://www.munenick.me/en/blog/hypr-rdp/ (hypr-rdp design write-up)
- https://github.com/leepokai/Codync/issues/319 (portal interfaces on Omarchy / Hyprland 0.57)

Omarchy

- https://github.com/omacom/omarchy/releases/tag/v4.0.0

Apple-device tooling on Linux

- https://github.com/doronz88/pymobiledevice3/blob/master/docs/guides/ios17-tunnels.md
- https://github.com/seemoo-lab/owl
