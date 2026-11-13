# Decisions

One entry per decision: what, why, what was rejected. Part 1 is what Mark decided and the
two items still open. Part 2 was decided in Milestone 0 and holds unless he says otherwise. Part 3 lists where the brief or the report was wrong.
Evidence for the protocol entries is in `PROTOCOL-GAP.md`, for licenses in `THIRD-PARTY.md`.

Status on 2026-11-13: Milestone 0, written in a cloud session; Mark then ran
`docs/hyprland-host/probe.sh` on the Omarchy machine and `PLAN.md` holds what it found.
Nothing rests on web research alone any more for what the compositor offers; what it does
with those protocols is first tested in M3.

## 1. Mark's answers (2026-11-13) and what is still open

**N1. Where the build runs: the Omarchy machine.** Mark ran the probe there; it has the
clone, Claude Code 2.1.323 and a working nested Hyprland. Before Session 2:
`git switch -c hyprland-host origin/claude/youthful-einstein-pmfvsj` and
`git remote add upstream https://github.com/Saffsanity/sill` (the brief's `/goal` reads
`upstream/main`).

**N2. The virtual display is a must-have.** Window streams use a headless output sized to
the device by default, as Sill for Mac's Virtual Display does; capture in place is the
fallback when it is switched off. Why: a window on a workspace that is not shown reportedly
renders about once every 5 s, so a covered window stays live reliably only on an output of
its own. This moves the headless output work in M4 from optional to required.

**N3. The port: 47470 by default, configurable, `0` for ephemeral.** Omarchy's ufw denies
incoming connections, so one rule must keep working across restarts. The device reads the
port from mDNS. Rejected: a random port saved at first run.

**N4. The name: `sill-host-hyprland` for now.** User-facing text says "an unofficial host
for the Sill app". **Still open:** the public package name, before any public release.

**N5. No Mac for now.** Fixtures are built by hand from the Swift definitions and checked
against `Scripts/sillclient.py`. Mark owns a Mac and can bring it up later: ask only if T4
fails in a way a known-good host would explain, or a fixture's shape is in doubt.

**N6. Code from afds/sill-linux may be ported, with credit** in `hosts/NOTICE`. PR #128
stays the base.

**N7. The nested test window is accepted** during T2 and T3. Input still goes only to an
instance the harness started (D11).

**N8. The supported Hyprland is the one the current Omarchy ships**: 0.56.2 on Omarchy
4.5.0 today, with a Lua configuration. Older versions and the old configuration language
are not supported; a newer version joins when Omarchy ships it.

**N9. Still open, and small: a work-log file.** Upstream keeps one short note per piece of
work in `docs/steps/` and its `CLAUDE.md` asks every branch to add one. The brief allows
this work no file outside `hosts/` and `docs/hyprland-host/`. Until Mark says otherwise
there is no such file: `PLAN.md` and this file are the record, and nothing outside those
two folders is touched.

## 2. Decided

**D1. Base commits.** Upstream `bf69067` (Sill 0.6.2, `origin/main` here and
`Saffsanity/sill` main on 2026-11-13). PR #128's head `173843b`, whose own base is `5c323e6`
(2026-10-15).

**D2. Import `hosts/` only.** The pull request's other changes are the Mac Viewer. It adds
nothing under `Scripts/`, so the hosts need nothing else from it. Rejected: its README
paragraph (about the Viewer).

**D3. One change to `Platform`, additive.** The trait has no clipboard, gestures, virtual
display, lock state or capability flags. M2 adds them as methods with default bodies, so the
Windows, X11 and synthetic backends compile unchanged:
`capabilities()`, `gesture()`, `clipboard_text()`, `set_clipboard_text()`,
`session_locked()`, `watch(events)` for window, clipboard and lock changes, and
`StreamConfig` gains the device's viewport and a virtual-display flag. Rejected: a second
trait beside it; a side channel only the Hyprland crate knows.

**D4. The backend captures and encodes; core never sees pixels.** That is the trait as
written. The Hyprland backend hands SHM frames (XRGB8888, as BGRA) to core's `FfmpegEncoder`.
The brief's fixed decision 7 stands. No dmabuf in the beta.

**D5. One capture path.** (All four globals are offered on Mark's 0.56.2.) `ext-image-copy-capture-v1` with output and toplevel
sources and a cursor session. No fallback to `hyprland-toplevel-export-v1` or
`wlr-screencopy`: Hyprland has had the `ext` path since 0.54, the only crate for the Hyprland
protocol is LGPL, and a second path doubles T2. This departs from a lead in the brief's
section 6, not from a fixed decision.

**D6. Our own Hyprland IPC client.** `hyprland-rs` is GPL-3.0 and older than 0.57's IPC.
Requests over `.socket.sock`, events over `.socket2.sock`, runtime changes through
`eval`: the probe sized a headless output with `eval 'hl.monitor({…})'` on 0.56.2.

**D7. TLS with pairing by default; unpaired keys refused in the handshake.** As the Swift
host does (`Sources/SillHost/DoorPolicy.swift:69-79`). The plain door needs
`--dev-plain-door`. Rejected: afds/sill-linux's way (finish the handshake, then goodbye
`pairingRequired`), which is friendlier but is not what the specification does.

**D8. No `hostVersion`.** `SillHost` sends none and no Release code compares it. A value
would claim a Mac version's features. `protocol` is 1.

**D9. Two test clients.** `Scripts/sillclient.py`, unmodified, is the independent check for
T1: it is a second implementation, so it catches a mistake the Rust crates share. A small
Rust client (`hosts/sill-testclient`) covers what it cannot: writing the stream out for a
decode check, and input in T3. Rejected: editing `sillclient.py`'s input guard (keeps
`Scripts/` identical to upstream); giving the Hyprland host a `--synthetic` flag (it would
be a lie the guard exists to prevent).

**D10. Declines.** Menus, audio, display stops, the cable, Direct Wireless: by leaving out
the field that announces each (`PROTOCOL-GAP.md`, sections 3 and 5).

**D11. Input goes only to an instance the harness started.** The backend takes the instance
signature and the Wayland socket as explicit arguments in test mode. The self-test refuses
to run when the signature equals the session's own, or when the harness did not create it.

**D12. Modifiers.** Command and Control both send Ctrl, Option sends Alt (PR #128's
mapping), so every PC host behaves alike. A setting sends Command as Super instead.

**D13. Typing.** A virtual keyboard with a keymap generated as text; text outside the keymap
through a temporary keymap carrying those keysyms (wtype's technique). libxkbcommon is not
linked unless M4 shows the compositor needs a resolved keymap.

**D14. The Desktop is one monitor.** The first monitor Hyprland lists, or the one a setting
names. Kind 47's stops are declined.

**D15. Window ids.** Core's ids are `u32`; Hyprland's addresses are 64-bit. The backend keeps
a table for the life of the process.

**D16. Shared Linux code moves, once.** Avahi publishing, `.desktop` apps and icons, and the
encoder probe live in the X11 crate today. M3 and M5 move them where both Linux backends
reach them, without changing what the X11 crate does.

**D17. Identity storage.** PR #128's: a `0700` folder, files `0600`, written through a
temporary file. Tests always pass `--config-dir` with a temporary folder and never touch
`~/.config`.

**D18. Locked session.** Detected over IPC (`hyprctl locked` answers on 0.56.2), reported as `locked: true` with a black
placeholder. Never unlocked by the host.

**D19. Hyprland's permissions.** Off on Mark's machine. If `ecosystem:enforce_permissions` is on, the daemon prints
the rule to add and stops. It never edits configuration. A denied capture returns black
frames, so the self-test checks pixels.

**D20. Milestone 0's commit.** On `claude/youthful-einstein-pmfvsj`, pushed to
`corduroy-dev/sill` only, by Mark's answer on 2026-11-13. The brief's "never push" holds for
Session 2.

## 3. Where the brief or the report was wrong

| Claim | Found |
|---|---|
| Report: clipboard (kind 32) arrived after the Rust port was written | It existed at the port's base. The port left it out, with `WindowList.clipboard`. |
| Brief M0: the hosts may need test tools the PR adds under `Scripts/` | The PR touches nothing under `Scripts/`. |
| Brief 5: NateHag's host is the best evidence of what a device needs | afds/sill-linux has the only dated device run and is closer to this work (Rust, same stack). NateHag's names no app version or device. |
| Report: both community hosts' licenses unverified | Both Apache-2.0. |
| Report: the red and blue swap is an NVIDIA bug | Also reproduced on AMD; fixed in Hyprland by a change merged in May 2026. T2's colour check stays. |
| Brief 6: size the headless output with a monitor rule; hypr-rdp as the technique | hypr-rdp uses `hyprctl keyword`, which a Lua configuration refuses: seen on 0.56.2, where `eval` worked. |
| Milestone 0's own web research: Omarchy 4.5 ships Hyprland 0.57 | It ships 0.56.2. |
| Report: Omarchy's Hyprland is 0.57.0 (from one user's report) | 0.56.2 on 4.5.0-3. |
| Brief 6: fall back to `hyprland-toplevel-export-v1` | Its Rust crate is LGPL-3.0, and the fallback is not needed from 0.54 on. |
| Brief 2: T1 runs upstream's client; T3 is "driven by the test client" | `sillclient.py` sends input only to a listener started with `--synthetic`. T3 needs another client. |
| Brief appendix B: T0's Windows check needs only the Rust target | `ring` compiles C even for `cargo check`, so it also needs a MinGW compiler. |
| Brief 3: virtual display is a should-have | A must-have: N2. |
| Brief 0 and 9: branch `hyprland-host`, an `upstream` remote, never push | Not true of a cloud session: see N1 and D20. |
| Brief 2: every tier is automatable but T4 | T2 and T3 cannot run without a GPU session, so they cannot run in CI or a cloud container. |
