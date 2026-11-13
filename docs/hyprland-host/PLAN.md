# Plan: a Hyprland host for the Sill app

The task list for `BRIEF.md`. A fresh session resumes from this file, `DECISIONS.md` and
`PROTOCOL-GAP.md`.

## Status

| Milestone | State | Gate evidence |
|---|---|---|
| M0 recon and plan | **done** | The three documents; the probe's output below. Two readings are still owed (globals, `vainfo`) |
| M1 import and baseline | not started | |
| M2 protocol up to date | not started | |
| M3 backend: see and list | not started | |
| M4 backend: act | not started | |
| M5 end to end | not started | |
| M6 package and hand over | not started | |

Open before M1: Mark's answers to `DECISIONS.md` part 1, and the two readings the probe missed.

## What is known about the machines

**The Omarchy machine**, from `probe.sh` run by Mark on 2026-11-13 (a Framework laptop):

| Item | Found | Was expected |
|---|---|---|
| Omarchy | 4.5.0-3, kernel 7.2.15 | 4.5.0 |
| Hyprland | **0.56.2** (2026-08-05), aquamarine 0.15.1, configured in Lua (`hyprland.lua`) | 0.57.x: wrong |
| Runtime changes | `hyprctl keyword` is refused under a Lua configuration ("Use eval"); `hyprctl eval 'hl.monitor({…})'` works | as expected, but already on 0.56 |
| Monitor | eDP-1, 2560x1600 at 165 Hz, scale 1, at layout position 12256x0 | |
| Window address | `0x55d903c734c0` (hex, fits 64 bits) | |
| Permissions | `ecosystem:enforce_permissions` false; no rule in the configuration | off |
| Lock state | `hyprctl locked` exists and answers `false` | |
| Keyboard | `us` | |
| GPU | AMD Radeon 880M / 890M (amdgpu), `/dev/dri/renderD128`; no NVIDIA | |
| FFmpeg | n9.0.2 with `hevc_vaapi`, `hevc_amf`, `hevc_vulkan`, `libx265` | |
| Rust | 1.99.1 through rustup (the workspace needs 1.92); `x86_64-pc-windows-gnu` and MinGW installed after the probe | |
| Python, tools | 3.13.12; `/usr/sbin/lsof`, `/usr/bin/openssl` and `/bin/ps` exist, so `sillclient.py`'s input guard works here | |
| Avahi | `avahi-daemon` active and enabled; `avahi-browse`, `avahi-publish` present | active |
| Firewall | ufw active and enabled | active |
| Test tools | `wtype`, `foot`, `wl-copy`, `notify-send`, `qrencode`, `ffprobe` present; `wev` missing (not needed: `sill-testwin`) | |
| Claude Code | 2.1.323 | 2.1.139 or later |
| **Nested instance** | Starts in 1 s as a window (`WAYLAND-1`, its own signature and `wayland-2`). A headless output was created, sized to 1280x800 by `eval`, and removed | as expected |

**Still unread on the machine** (the tools were installed after the probe ran):
- The Wayland globals: `wayland-info` was missing. The capture, virtual input and data
  control protocols are therefore still expected, not seen.
- VA-API's HEVC encode profile: `vainfo` was missing.

**What the nested run taught the harness** (task 3.2):
- `hyprctl dispatch exit` fails under Lua ("expected a dispatcher"). Stop the instance by
  its process, or find the Lua dispatcher.
- After the instance was stopped, its folder stayed under `$XDG_RUNTIME_DIR/hypr`. The
  harness removes the folder of an instance it started, and compares `hyprctl instances`
  before and after, not the folders.
- An empty configuration raises Hyprland's error overlay and starts Xwayland. The harness
  writes a valid minimal Lua configuration with Xwayland off.
- The nested `WAYLAND-1` appears to come up at scale 2 (the headless output was placed at
  x 638, half its 1276 pixels): frame sizes and pointer mapping must not assume scale 1.

**The cloud container used for M0** (Ubuntu 24.04): Rust 1.97, Python 3.13, FFmpeg with
libx265, Docker client. No Hyprland, Wayland, GPU, Avahi, pacman, Swift or MinGW; `lsof` is
at `/usr/bin` only. T0 and most of T1 can run in such a container; T2 and T3 cannot.

## Architecture

```
hosts/
  sill-protocol/          wire format, TLS, pairing            (PR #128, brought up to date in M2)
  sill-host-core/         doors, sessions, settings, encoder   (PR #128, M2; one Platform change)
  sill-host-windows/      untouched; must keep type-checking
  sill-host-linux/        X11; untouched but for code moved out to share (D16)
  sill-host-hyprland/     NEW: the backend, the daemon and its CLI
    src/ipc.rs            Hyprland sockets: requests, events, instance choice
    src/wl/               registry, capture, virtual pointer, virtual keyboard, data control
    src/keymap.rs         HID usage to evdev, generated keymap, text keysyms
    src/vdisplay.rs       headless output: create, size, move a window, remove, stale cleanup
    src/catalog.rs        windows, apps, icons, thumbnails
    src/selftest.rs       --self-test, called by T2
    src/daemon.rs, cli.rs pair, devices, unpair, status over a socket in $XDG_RUNTIME_DIR
  sill-testclient/        NEW: Rust test client for the decode check and T3
  sill-testwin/           NEW: a Wayland test window: colour bars, logs the keys and text it gets
  scripts/verify.sh       T0 to T3, one line each
  scripts/nested.sh       starts and stops the nested Hyprland the tests use
  NOTICE, CLAUDE.md, NOTES-hyprland.md
```

Data path: Hyprland → SHM frame (XRGB8888) → core `FfmpegEncoder` (VA-API, NVENC or libx265,
a subprocess) → `StreamSink` → core's door. Input path: core → `Platform::inject` → virtual
pointer or keyboard. Nothing is captured while no device is connected.

The `Platform` change (D3), made once in M2 by the orchestrator, defaults in every method:

```rust
fn capabilities(&self) -> Capabilities;            // gestures, clipboard, key_repeat, virtual_display
fn gesture(&self, gesture: Gesture);
fn clipboard_text(&self) -> Option<String>;
fn set_clipboard_text(&self, text: &str);
fn session_locked(&self) -> bool;
fn watch(&self, events: Arc<dyn PlatformEvents>);  // windows, clipboard or lock state changed
// StreamConfig gains: viewport: Option<Viewport>, virtual_display: bool
```

## Milestones

Owner is the agent that writes; `test-runner` runs every check; `reviewer` reads each gate's
diff. Writers never share a file. Checks run from `hosts/`.

### M1. Import and baseline

| # | Task | Owner | Files | Check |
|---|---|---|---|---|
| 1.1 | Fetch `refs/pull/128/head` (`173843b`), check out `hosts/` only, commit with Alexander Deutsch as author | orchestrator | `hosts/**` | `git diff --stat upstream/main -- Sources iOSClient Package.swift` is empty |
| 1.2 | `hosts/NOTICE` (upstream, PR #128); confirm the three lock entries' licenses with `cargo metadata` | implementer | `hosts/NOTICE`, `docs/hyprland-host/THIRD-PARTY.md` | file exists; table updated |
| 1.3 | Scoping note at the top of root `CLAUDE.md`; `hosts/CLAUDE.md` (commands, section 4's constraints, "every change ends with its verify tier") | implementer | `CLAUDE.md`, `hosts/CLAUDE.md` | a scout confirms the note does not trip `Tests/checks/repo-rules` (it cannot run on Linux: it needs swiftc) |
| 1.4 | `verify.sh` with T0; the Windows line prints SKIP with the install command when the target or MinGW is missing | implementer | `hosts/scripts/verify.sh` | `scripts/verify.sh T0` |

Gate: `T0 PASS` on the workspace as imported.

### M2. Protocol brought up to date

| # | Task | Owner | Files | Check |
|---|---|---|---|---|
| 2.1 | Kinds 32 and 44 (43 and 47 named, never sent); the fields of `PROTOCOL-GAP.md` section 4; `ViewportBounds`; `WindowCommand.action` as an enum; a fixture test per shape | protocol-porter | `hosts/sill-protocol/**` | `cargo test -p sill-protocol` |
| 2.2 | The `Platform` change above; synthetic backend updated | orchestrator | `hosts/sill-host-core/src/platform.rs`, `synthetic.rs` | `cargo check --workspace` |
| 2.3 | Core: kind 44 to `request_keyframe` (one a second); viewport bounds; the locked list and placeholder; `sessionPaired`; capability fields from `capabilities()`; clipboard and gesture routing | protocol-porter | `hosts/sill-host-core/src/{coordinator,server,catalog,config}.rs` | `cargo test -p sill-host-core` |
| 2.4 | TLS with pairing by default, `--dev-plain-door` for the plain door; confirm the handshake refusal against `DoorPolicy.swift` | protocol-porter | `hosts/sill-host-core/src/{host,door,pairing}.rs` | tests for both doors |
| 2.5 | `sill-testclient`: pinned TLS, pair by code, pick, write the stream as Annex B, kind 44, an unknown kind, goodbye; refuses any host not on loopback | implementer | `hosts/sill-testclient/**` | `cargo test -p sill-testclient` |
| 2.6 | T1 in `verify.sh`: `sill-host-synthetic` on loopback with a temporary `--config-dir`, driven by `Scripts/sillclient.py` (pairing, pinned reconnect after a restart, refusal, list, pick, input, kind 44, clipboard if built) and by `sill-testclient` (60 frames decoded by `ffprobe` at the announced size) | implementer | `hosts/scripts/verify.sh`, `hosts/scripts/t1/**` | `scripts/verify.sh T1` |
| 2.7 | Security review: doors, pairing, key storage | reviewer | none | no blocker |

Gate: `T1 PASS`. Note for 2.6: `sillclient.py` needs `/usr/sbin/lsof`, `/usr/bin/openssl`
and `/bin/ps`; where one is missing T1 prints FAIL saying which, never SKIP as a pass.

### M3. Hyprland backend: see and list

| # | Task | Owner | Files | Check |
|---|---|---|---|---|
| 3.1 | IPC client: `monitors`, `clients`, `eval`, `output`, the event socket; unit tests on recorded JSON | implementer | `sill-host-hyprland/src/ipc.rs` | `cargo test -p sill-host-hyprland ipc` |
| 3.2 | `nested.sh`: start Hyprland with a valid minimal Lua configuration (Xwayland off) in a temporary folder, print its signature and Wayland socket, stop it by its process, remove its own runtime folder, compare `hyprctl instances`, monitor and client lists before and after | implementer | `hosts/scripts/nested.sh` | `scripts/nested.sh selfcheck` |
| 3.3 | `sill-testwin`: an SHM window with colour bars that logs keys and text | implementer | `hosts/sill-testwin/**` | runs in the nested instance |
| 3.4 | Output capture into `FfmpegEncoder`; frame size and pixel colours against the bars, red and blue the right way round | wayland-engineer | `src/wl/{mod,capture}.rs` | self-test: output |
| 3.5 | Toplevel capture, updating while covered; cursor session to kind 14 (in points); pointer place for kind 26 | wayland-engineer | `src/wl/capture.rs`, `src/wl/cursor.rs` | self-test: window, covered, cursor |
| 3.6 | Catalog: windows with titles and apps, `u32` ids, change events; apps and icons from the shared `.desktop` code (D16) | implementer | `src/catalog.rs`, the moved module | window list equals `hyprctl clients -j` |
| 3.7 | `--self-test` and the capture half of T2 | implementer | `src/selftest.rs`, `verify.sh` | `scripts/verify.sh T2` (capture) |

Gate: the capture half of T2 passes in the nested instance.

### M4. Hyprland backend: act

| # | Task | Owner | Files | Check |
|---|---|---|---|---|
| 4.1 | Virtual pointer: absolute moves mapped to the streamed output or window, buttons, scroll with its phases | wayland-engineer | `src/wl/pointer.rs` | `hyprctl cursorpos`; a click focuses the test window |
| 4.2 | Virtual keyboard: keymap, modifiers (D12), text including `é`, `€`, `ж`; every key released when a device leaves | wayland-engineer | `src/wl/keyboard.rs`, `src/keymap.rs` | text arrives intact in `sill-testwin` |
| 4.3 | Headless output: create, size to the viewport, move the window, remove; outputs left by a crash removed at start | wayland-engineer | `src/vdisplay.rs` | created, sized, used, removed; lists equal after |
| 4.4 | Focus, fit, close and full screen; lock and permission detection | implementer | `src/window.rs`, `src/session.rs` | self-test steps |
| 4.5 | Optional: clipboard over data control; gestures to workspace dispatchers | wayland-engineer | `src/wl/clipboard.rs`, `src/gestures.rs` | self-test steps |
| 4.6 | Security review: input injection | reviewer | none | no blocker |

Gate: all of T2, cleanup included.

### M5. End to end

| # | Task | Owner | Files | Check |
|---|---|---|---|---|
| 5.1 | Encoder choice (VA-API, NVENC, libx265) shared by both Linux backends | implementer | the shared module | unit test; `status` names the encoder |
| 5.2 | Avahi publishing shared; TXT `r` and `p` | implementer | the shared module | `avahi-browse -rt _sill._tcp` |
| 5.3 | Daemon and CLI; the pairing code and QR in the terminal and as a notification | implementer | `src/{daemon,cli}.rs` | CLI tests on loopback |
| 5.4 | Frame rate and capture-to-encode latency, p50 and p95, recorded | wayland-engineer | `src/metrics.rs` | numbers in the T3 output |
| 5.5 | T3 in `verify.sh` | implementer | `verify.sh`, `hosts/scripts/t3/**` | `scripts/verify.sh T3` |

Gate: `T3 PASS`.

### M6. Package and hand over

| # | Task | Owner | Files | Check |
|---|---|---|---|---|
| 6.1 | `PKGBUILD`, the `systemd --user` unit, the Omarchy menu snippet in the installed version's format | implementer | `hosts/packaging/hyprland/**` | `makepkg` builds; nothing is installed |
| 6.2 | `hosts/NOTES-hyprland.md`: verified and not | orchestrator | that file | |
| 6.3 | `docs/hyprland-host/BETA-TEST.md`: T4 step by step, what to capture on failure, the "Update Sill on …" lines that are expected | orchestrator | that file | |
| 6.4 | Review of the whole diff | reviewer | none | no open finding |

Gate: `verify.sh` all PASS, review clean, the package builds.

## Risks, most likely first

1. **The compositor differs from the research.** The probe already moved the version from
   0.57 to 0.56.2. The Wayland globals are still unread; M3's first task reads them before
   any design rests on them (D5).
2. **Covered windows stop updating.** Addressed by the headless output (N2). If Mark keeps it
   optional, T2's covered-window check may fail by design.
3. **Virtual pointer mapping.** Hyprland's source stores the output a pointer is bound to and
   does not appear to read it; absolute moves may span the whole layout. Mark's own monitor
   sits at 12256x0, so a layout does not start at the origin. 4.1 computes the mapping itself
   and T2 checks the result.
4. **The keymap.** Whether the compositor accepts a generated keymap and how a temporary one
   interacts with held modifiers is untested. 4.2 owns it; D13 names the fallback.
5. **The app on a real device.** No Rust host from PR #128 has met the iOS app. T1 with an
   independent client narrows this; only T4 closes it.
6. **Frame rate on SHM.** Copying 1080p frames may miss 30 fps. Measured in 5.4; dmabuf is
   after the beta.

## For Session 2

- Read `DECISIONS.md` part 1 first: Mark's answers change M4's size (N2) and where this runs (N1).
- If `.claude/agents/` was not picked up at session start, delegate to `general-purpose` with
  the agent file's text and its model.
- Never inject input outside an instance `nested.sh` started (D11).
- When the conversation compacts, keep: the milestone, failing checks, open decisions, and
  which agent owns which files.
