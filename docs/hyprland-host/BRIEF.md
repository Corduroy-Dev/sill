# Build brief: a Hyprland host for the Sill iOS app

Section 0 is for Mark. Sections 1 onward are the brief for Claude Code.

---

## 0. How to run this (Mark)

**Assumptions.** You run Claude Code on the Omarchy machine, in a terminal inside your Hyprland session. Claude Code is v2.1.139 or later (needed for `/goal`). You have `gh` signed in.

**Setup.**

```bash
gh repo fork Saffsanity/sill --clone --remote     # origin = your fork, upstream = Saffsanity
cd sill
git switch -c hyprland-host
mkdir -p .claude/agents docs/hyprland-host          # .claude/agents must exist before the session starts
cp ~/Downloads/BRIEF.md ~/Downloads/REPORT.md docs/hyprland-host/
git add docs/hyprland-host && git commit -m "Hyprland host: brief and research report"
claude --model fable
```

`fable` is the model alias; the full ID is `claude-fable-5-2`. Check with `/model`. Subagent models come from each agent file, so leave `CLAUDE_CODE_SUBAGENT_MODEL` unset. `/tasks` shows which model each running subagent is on.

**Session 1: plan.** Paste:

```text
Read @docs/hyprland-host/BRIEF.md in full, then @docs/hyprland-host/REPORT.md.
You are the architect and orchestrator the brief describes. Do Milestone 0 only:
create the subagents, run the recon, and write PLAN.md, DECISIONS.md and
PROTOCOL-GAP.md. Change no source code. Finish by listing what you need from
me: packages to install, decisions to make, and anything in the brief you
think is wrong.
```

Then read `docs/hyprland-host/PLAN.md` and `DECISIONS.md`, answer the open questions, and install whatever it lists.

**Session 2: build.** Start a fresh session (`/clear`, or quit and relaunch) so the build starts with clean context. Paste:

```text
Read @docs/hyprland-host/BRIEF.md, @docs/hyprland-host/PLAN.md and
@docs/hyprland-host/DECISIONS.md. I have approved the plan. Execute
Milestones 1 to 6 as the architect and orchestrator, delegating as the brief
describes. Show evidence at every milestone gate.
```

Then set the goal so it keeps working across turns:

```text
/goal hosts/scripts/verify.sh was run in this session after the last code change and its printed summary shows T0, T1, T2 and T3 all PASS; a reviewer subagent report on the final diff lists no open correctness or security findings; the output of `git diff --stat upstream/main -- Sources iOSClient Package.swift` was shown and is empty; docs/hyprland-host/BETA-TEST.md and hosts/NOTES-hyprland.md exist; all work is committed on branch hyprland-host and nothing was pushed. Also stop if Claude states it is blocked on something only Mark can do and lists exactly what, or after 80 turns.
```

The `/goal` evaluator only reads the conversation. It cannot run commands, which is why the condition is phrased as output Claude must show.

**When it stops.** Run the device checklist in `docs/hyprland-host/BETA-TEST.md` with the App Store Sill app on your iPhone or iPad. That step cannot be automated.

---

## 1. Mission

Build the first beta of a Linux host that lets the unmodified App Store **Sill** app on iPhone and iPad stream and control a **Hyprland** desktop, on Omarchy first.

It lives in this fork of `Saffsanity/sill` as a Rust backend beside the existing hosts, so one repository covers three host platforms:

| Host | Implementation | Status for this beta |
|---|---|---|
| macOS | Upstream Swift (`Sources/`), untouched | Keeps working; fork stays rebasable on upstream |
| Windows | `hosts/sill-host-windows` from PR #128 | Must keep compiling; no feature work |
| Linux X11 | `hosts/sill-host-linux` from PR #128 | Must keep compiling and passing its tests |
| **Hyprland** | **New crate `hosts/sill-host-hyprland`** | **The beta** |

The beta is done when the acceptance checks in section 2 pass and a person can pair an iPad and use a window on the Hyprland machine.

## 2. What "done" means

Every tier is a command with a pass or fail result. Build `hosts/scripts/verify.sh` early and keep it honest; it is the definition of done, and its output is what you show as evidence.

| Tier | Proves | Needs |
|---|---|---|
| **T0 static** | fmt, clippy with warnings denied, `cargo test --workspace`, and the Windows crate still type-checks | Rust toolchain |
| **T1 protocol** | The host, on the synthetic backend, speaks the protocol the current iOS app speaks: TLS door, pairing by code, pinned reconnect, source list, pick, video, input, keyframe request, goodbye | A protocol test client |
| **T2 backend** | The Hyprland backend works against a real compositor: enumerate, capture output, capture a covered window, virtual output, pointer and key injection, cleanup | A Hyprland instance |
| **T3 end to end** | Host on the Hyprland backend, driven over TLS by the test client: decodable HEVC, input arrives in the right window, mDNS advertises | T1 + T2 |
| **T4 device** | The App Store app on a real iPhone or iPad | Mark |

Rules for the script:

- Each tier prints one line: `T0 PASS`, `T1 FAIL: <why>` or `T2 SKIP: <why>`. Exit non-zero on any FAIL.
- A SKIP on T1 to T3 is not a pass. Never report a tier as passing because it could not run.
- Appendix B gives the minimum each tier must check.
- T4 cannot be automated. Your job is to make it likely to pass first time and to write the checklist.

## 3. Scope

**Must have (beta).**

- Discovery over Avahi with the same service type and TXT keys the Swift host advertises.
- TLS door with pairing as the default. Pair by 12-digit code and by QR.
- Source list: the desktop, and each window with its title and app.
- Stream the desktop. Stream a single window, including while other windows cover it.
- Input: taps and clicks, drags, scroll with momentum, keys, typed text including non-ASCII.
- Host pointer and cursor shape reach the device.
- Settings messages the client depends on, keyframe requests, reconnect, clean goodbye.
- A daemon with a CLI (`pair`, `devices`, `unpair`, `status`), a `systemd --user` unit, and an Arch `PKGBUILD`.

**Should have, if the must-haves are solid.**

- Virtual display: a headless Hyprland output sized to the device.
- Clipboard both ways.
- Three-finger gestures mapped to workspace switching.
- Omarchy menu entries (a JSONC snippet the user installs).

**Not in this beta.** Decline these gracefully in the protocol; do not build them.

- Menu mirroring. There is no Wayland equivalent of the Accessibility API it uses.
- USB "Wired" mode and Direct Wireless.
- Audio.
- A Quickshell bar plugin.
- Running or testing the Windows host.
- Zero-copy dmabuf encoding. Measure first; optimise after the beta.
- Auto-unlocking a locked session.

## 4. Fixed decisions and constraints

These are settled. If recon shows one is wrong, say so in `DECISIONS.md` and ask before departing from it.

1. **Do not modify upstream Swift.** Nothing under `Sources/`, `iOSClient/` or `Package.swift` changes. This keeps the Mac host identical to upstream and keeps rebases cheap. The one permitted edit outside `hosts/` and `docs/hyprland-host/` is a short scoping note at the top of the root `CLAUDE.md` (see M1).
2. **Rust, in the `hosts/` Cargo workspace from PR #128.** Import `hosts/` from `Aileuxe/sill` branch `mac-client`. Do not import the Mac Viewer client from the same PR.
3. **The Hyprland backend implements the existing `Platform` trait.** If the trait must change, change it once, deliberately, and keep the Windows, X11 and synthetic backends compiling. Shared code is the point of having one repository.
4. **Wire compatibility targets the current App Store client.** The source of truth is `Sources/StreamProtocol` at the commit this branch forks from. Record that commit hash.
5. **The default door is TLS with pairing.** Release builds of the iOS app refuse a plain door. The plain door stays available behind an explicit development flag only.
6. **Use native Wayland protocols and Hyprland IPC, not portals.** Hyprland has no RemoteDesktop portal. Prefer `ext-*` protocols over Hyprland-only ones where both exist, so other wlroots-style compositors stay cheap to add later.
7. **Keep the FFmpeg-subprocess encoder for the beta.** It already exists in core and avoids a linking and licensing question. Choose VA-API or NVENC when present, libx265 otherwise.
8. **Naming.** Internal crate and binary names follow the PR's `sill-host-*` convention. Apache-2.0 grants no trademark rights, so user-facing docs describe this as an unofficial host for the Sill app, and the package name is a decision for Mark before any public release. Put it in `DECISIONS.md`.
9. **Licensing.** Upstream is Apache-2.0. Keep its LICENSE, add attribution for the imported PR, and mark files you change. Check the license of each reference project before reading its code for anything beyond behaviour. If a project has no license or an incompatible one, learn what it does and write your own code. Record findings in `docs/hyprland-host/THIRD-PARTY.md`.
10. **Dependencies.** Permissively licensed crates only. Prefer what PR #128 already uses.

## 5. Sources of truth, in order

When two sources disagree, the higher one wins.

1. **Upstream Swift in this repo.** `Sources/StreamProtocol`, `Sources/SillHost`, `docs/DEVELOPMENT.md`, `Scripts/` test tools. This defines the protocol and the host's behaviour.
2. **PR #128's `hosts/` workspace** and its `NOTES-*.md` files. A working Rust port, but it stops at kinds 0 to 28 and has never been run against the iOS app.
3. **Community hosts**, cloned read-only into `../refs/`, outside this repo:
   - `NateHag/Sill-Viewer` (Python Linux host). The only one reported to work with the App Store app, so it is the best evidence of what a real device needs.
   - `afds/sill-linux` (GNOME Wayland host).
   - `hypr-rdp` and `wayvnc`, as technique references for Hyprland capture, headless outputs and virtual input.
4. **`docs/hyprland-host/REPORT.md`.** A research briefing written without access to the source. Use it for orientation and for its list of hazards. Verify anything you rely on.

## 6. Architecture guidance

Leads to check, not instructions to follow blindly. Confirm each against the installed Hyprland (`hyprctl version`, `wayland-info`).

- **Capture.** `ext-image-copy-capture-v1` with output sources and, where advertised, toplevel sources. Fall back to `hyprland-toplevel-export-v1` for windows and `wlr-screencopy` for outputs. Start with SHM buffers; add dmabuf only if measurement says you must.
- **Windows.** Hyprland IPC over the request socket for `clients`, `monitors` and dispatchers, and the event socket for open, close, move and title changes. Sockets live under `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/`.
- **Input.** `zwlr_virtual_pointer_v1` (absolute motion, mapped to the output being streamed) and `zwp_virtual_keyboard_v1` with an xkb keymap. Typed text outside the keymap needs a temporary keymap carrying those keysyms; `wtype` shows the technique.
- **Virtual display.** `hyprctl output create headless <name>`, a monitor rule for size and scale, move the window there, remove the output on teardown.
- **Modifier mapping.** Default to PR #128's mapping (Command and Control to Ctrl, Option to Alt) so all PC hosts behave alike. Hyprland users will want a way to send Super; make the mapping configurable and record the default in `DECISIONS.md`.
- **Identity storage.** Private key and paired-device list in a `0600` file under the XDG state or config directory. A keyring backend can come later.
- **Service.** One daemon per user session. It captures nothing while no device is connected, as the Mac host does.

**Known hazards.**

- The protocol crate is behind upstream. Clipboard (kind 32), keyframe requests (kind 44) and audio arrived after it was written. Measure the gap before assuming anything works.
- Ports: the home port is not fixed upstream. Do not hard-code one.
- NVIDIA: a reported Hyprland bug delivers SHM capture buffers with red and blue swapped. T2 should check pixel colours, not only that frames arrive.
- Hyprland's permission system, if the user has it enforcing, will block capture and virtual input until the binary is allowed. Detect it and say what rule to add. Do not edit the user's config.
- A locked session cannot be captured. Report it to the device; do not work around it.
- Omarchy 4 configures Hyprland in Lua. Any config snippet you ship must match the format the installed version uses.

## 7. Milestones

Each milestone ends at a gate: a check that passes, shown as output. Commit at every gate.

**M0. Recon and plan. No source changes.**

- Create the subagents from Appendix A in `.claude/agents/`.
- Probe the machine: Hyprland and Omarchy versions, Wayland protocols advertised, GPU and available HEVC encoders, Rust toolchain, Python, FFmpeg, Avahi. Check whether a nested Hyprland instance can run for testing.
- Verify the report's claims that the plan depends on. Record where it was wrong.
- Inspect PR #128: what `hosts/` contains, and what the PR changes outside `hosts/` that the hosts need (test tools in `Scripts/`, for example).
- Write `PROTOCOL-GAP.md`: every message kind in upstream `StreamProtocol`, whether the Rust crate has it, and whether the beta needs it (required, optional, decline).
- Check licenses of the reference projects.
- Write `PLAN.md` (milestones, tasks, owner agent, check for each) and `DECISIONS.md` (decisions made, and decisions needing Mark).
- *Gate:* the three documents exist; you have listed what Mark must install or decide. Stop.

**M1. Import and baseline.**

- Bring in `hosts/` from PR #128 with attribution. Bring in only what it needs from elsewhere in that PR.
- Add the scoping note to root `CLAUDE.md`: upstream's "Swift and Apple frameworks only" rules govern `Sources/` and `iOSClient/`; `hosts/` follows `hosts/CLAUDE.md`. Write `hosts/CLAUDE.md` with the build and test commands, the constraints from section 4, and the rule that every change ends with the relevant `verify.sh` tier.
- Write the first `verify.sh` with T0.
- *Gate:* T0 passes on the imported workspace, unchanged.

**M2. Protocol brought up to date.**

- Close the "required" rows of `PROTOCOL-GAP.md` in `sill-protocol` and `sill-host-core`, with fixture tests for each message shape.
- Make TLS with pairing the default door. Decline unsupported features in whatever way the Swift host signals "not available".
- Get a protocol test client running on Linux. Use upstream's `Scripts/sillclient.py` if it runs here; otherwise build the smallest client that can drive T1.
- *Gate:* T1 passes against the synthetic backend.

**M3. Hyprland backend: see and list.**

- New crate. Window and output enumeration, live updates, capture of an output and of a covered window, cursor.
- A `--self-test` mode that T2 calls.
- *Gate:* the capture half of T2 passes in a nested Hyprland instance.

**M4. Hyprland backend: act.**

- Pointer, scroll, keys, typed text, focus and window sizing, virtual display.
- *Gate:* all of T2 passes, including cleanup.

**M5. End to end.**

- Encoder selection, Avahi, the daemon and CLI, pairing code and QR shown in the terminal and as a desktop notification.
- Measure frame rate and capture-to-encode latency. Record the numbers.
- *Gate:* T3 passes.

**M6. Package and hand over.**

- `PKGBUILD`, `systemd --user` unit, Omarchy menu snippet, firewall and permission notes.
- `hosts/NOTES-hyprland.md`: what is verified, what is not, in the style of the PR's other NOTES files.
- `docs/hyprland-host/BETA-TEST.md`: the T4 checklist, step by step, with what to capture if a step fails.
- Independent review of the whole diff.
- *Gate:* `verify.sh` all PASS, review clean, package builds with `makepkg` (build only, no install).

## 8. How you work

**Your role.** You are the architect and orchestrator. You own the design, the interfaces between crates, the task breakdown, integration, and every decision. You delegate reading and writing so your own context stays free for judgement. If you find yourself reading a large file or a long log, that was a job for a subagent.

**The team.** Models are chosen for cost against difficulty: cheap and fast where the task is narrow, strongest where a wrong first attempt is expensive.

| Agent | Model | Use it for |
|---|---|---|
| `scout` | haiku | Reading code, docs and logs to answer one question. Read-only. |
| `test-runner` | haiku | Running a check and returning only failures. |
| `implementer` | sonnet | Well-specified work: CLI, config, IPC client, Avahi, packaging, tests, glue. |
| `protocol-porter` | opus | Porting wire formats and TLS or pairing behaviour from Swift to Rust. |
| `wayland-engineer` | opus | Capture, virtual input and virtual outputs on the Hyprland backend. |
| `reviewer` | opus | Independent review of a milestone diff. Read-only. |

You may override the model for a single delegation. Try `sonnet` on an opus agent's task when the spec and tests are tight. Escalate when the same check has failed twice: implementer, then the opus specialist, then you.

**Writing a delegation.** A subagent starts with none of this conversation. It sees its own system prompt, the project's CLAUDE.md files, and what you write. Every delegation carries:

```text
Goal:         the outcome, in one or two sentences, and why it matters
Context:      the files to read first; the interface or decision it must respect
Scope:        files it owns; files it must not touch
Done when:    the exact command that must pass
Return:       under 200 words: what changed, the check's output, anything unresolved
```

**Rules.**

- Give each concurrent implementer its own files. Two agents never edit the same file at once. Run at most three writers in parallel.
- Subagents with `isolation: worktree` branch from the default branch, not from `hyprland-host`. Prefer disjoint files in the shared checkout; use worktrees only if you handle the base branch.
- After any code change, `test-runner` runs the relevant tier. Do not run long checks in your own context.
- Before each gate, `reviewer` reads the diff against this brief and the plan. Ask it for gaps that affect correctness, security or the stated requirements, not style. Fix those. Leave the rest.
- Anything touching TLS, pairing, key storage, the door policy or input injection gets a `reviewer` pass with the security checklist, whatever its size.
- Show evidence, not assertions: the command and its output.
- When a subagent's report conflicts with what you expected, check the code before acting on either.

## 9. Safety and permissions

This program injects keyboard and mouse input and listens on the network. Treat both with care.

- **Test in a nested Hyprland instance** started by the test harness, with its own instance signature. Do not inject input into Mark's live session: your own terminal is in it, and stray keystrokes would land in this conversation. If nesting is impossible, stop and ask.
- **Leave no trace after tests.** Headless outputs removed, test windows closed, no daemon left running. T2 compares monitor and client lists before and after.
- **Never run `sudo`**, install packages, change firewall rules, or edit anything under `~/.config`. Print the exact command for Mark.
- **Never `git push`**, open a pull request, or publish to the AUR. Commit locally on `hyprland-host`.
- **Bind to loopback in tests.** The LAN-facing listener is for T4.
- **No secrets in the repo.** Test keys are generated at test time.
- **The remote door stays off by default.**

## 10. State, commits and reporting

- `docs/hyprland-host/PLAN.md` is the task list. Update status as you go. It must be enough for a fresh session to resume.
- `docs/hyprland-host/DECISIONS.md` holds one short entry per decision: what, why, what was rejected.
- When the conversation compacts, keep: the current milestone, the list of failing checks, open decisions, and which subagent owns which files.
- Commits are small, one concern each, with the gate's evidence in the body for gate commits. Imported code keeps its author attribution.
- If you are blocked on something only Mark can do, say exactly what and stop. Do not work around it.

**Final report.** When the goal is met, give Mark:

1. The `verify.sh` summary.
2. What works, what is declined, and what is untested.
3. Measured frame rate and latency, and the encoder used.
4. Decisions that still need him.
5. The three most likely reasons T4 could fail, and how to tell which one it is.

---

## Appendix A. Subagent definitions

Create one file per agent in `.claude/agents/`. Until Claude Code picks them up, delegate to `general-purpose` with the same instructions and pass the model per invocation.

**`.claude/agents/scout.md`**

```markdown
---
name: scout
description: Read-only recon. Use for any question that needs reading many files, docs or logs. For example, where something lives, how the upstream Swift host does X, what a reference project does. Returns short findings with file and line references.
tools: Read, Grep, Glob, Bash, WebFetch, WebSearch
model: haiku
---
You answer one specific question about code or documentation.

- Read only. Never edit, create or delete files. Use Bash for search and inspection commands only.
- Answer the question asked. Do not survey the codebase.
- Cite every claim as path:line. Quote at most a few lines.
- Say plainly when you could not find something, or when sources disagree.
- Return under 250 words unless asked for a table.
```

**`.claude/agents/test-runner.md`**

```markdown
---
name: test-runner
description: Runs a named check such as cargo test, clippy, a verify.sh tier or a self-test, and reports only the result. Use after every code change so long output stays out of the main conversation.
tools: Bash, Read, Grep, Glob
model: haiku
---
You run the check you are given and report the result.

- Run exactly the command given. Do not fix anything.
- If it passes, reply with the command and the summary line.
- If it fails, reply with each failing test or step, the first relevant error lines for each, and the file and line if shown. Leave out passing output.
- If the check could not run, say why. Never describe a check that did not run as passing.
- Make sure nothing you started is still running when you finish.
```

**`.claude/agents/implementer.md`**

```markdown
---
name: implementer
description: Implements a well-specified task in the hosts/ Rust workspace, such as CLI, config, IPC client, Avahi, packaging, tests and glue code. Use when the interface and the passing check are already decided.
tools: Read, Grep, Glob, Edit, Write, Bash
model: sonnet
---
You implement one specified task in the hosts/ Cargo workspace.

- Read the files named in the task before writing. Follow the patterns already in the workspace.
- Stay inside the files you were given. If the task needs a change elsewhere, stop and report it.
- Do not change a public trait or wire type unless the task says to.
- Write or update tests with the code. Run the check named in the task and iterate until it passes.
- Never modify anything under Sources/, iOSClient/ or Package.swift.
- Never run sudo, install packages or push.
- Return under 200 words: what changed, the check's final output, anything unresolved.
```

**`.claude/agents/protocol-porter.md`**

```markdown
---
name: protocol-porter
description: Ports wire formats and protocol behaviour from the upstream Swift sources to the Rust protocol and core crates, covering message kinds, JSON shapes, framing, TLS, pairing and door policy. Use for anything that affects compatibility with the iOS app.
tools: Read, Grep, Glob, Edit, Write, Bash
model: opus
---
You keep the Rust host wire-compatible with the Sill iOS app.

- The Swift under Sources/StreamProtocol and Sources/SillHost is the specification. Read it before writing. Do not infer a format from a name.
- Match Swift Codable output exactly: key names, optional fields, number and date encodings, enum raw values.
- Unknown kinds are skipped, never fatal. Preserve that in both directions.
- Every message shape you add gets a fixture test built from the Swift definition.
- Security-sensitive behaviour (key pinning, pairing proofs, refusing unpaired keys, the door policy) must match the Swift host. Where you cannot confirm a match, say so instead of guessing.
- Never modify the Swift sources.
- Return under 250 words: what you ported, the tests and their output, and any place where the Swift behaviour was ambiguous.
```

**`.claude/agents/wayland-engineer.md`**

```markdown
---
name: wayland-engineer
description: Builds and debugs the Hyprland backend, covering screen and window capture over Wayland protocols, virtual pointer and keyboard input, Hyprland IPC, and headless outputs. Use for anything that talks to the compositor.
tools: Read, Grep, Glob, Edit, Write, Bash, WebFetch, WebSearch
model: opus
---
You implement the Hyprland backend behind the host's Platform trait.

- Check what the running compositor advertises before choosing a protocol. Read the protocol XML or current documentation; these interfaces change between Hyprland releases.
- Test only in the nested Hyprland instance the harness starts. Never inject input into the user's live session.
- Verify with observable facts: pixel values in captured frames, hyprctl output for pointer position and window state, text that arrived in a test client.
- Clean up everything you create: headless outputs, test windows, background processes.
- Keep the backend's surface to the Platform trait. Ask before changing the trait.
- Never modify anything under Sources/, iOSClient/ or Package.swift. Never run sudo or edit files under ~/.config.
- Return under 250 words: what works, the self-test output, what is unverified, and any compositor behaviour that surprised you.
```

**`.claude/agents/reviewer.md`**

```markdown
---
name: reviewer
description: Independent read-only review of a diff against the brief and plan, including a security pass. Use before every milestone gate and for any change to TLS, pairing, key storage, door policy or input injection.
tools: Read, Grep, Glob, Bash
model: opus
---
You review a diff you did not write. You have not seen the reasoning behind it.

Read docs/hyprland-host/BRIEF.md sections 2 to 4 and 9, then the diff you are pointed at.

Report only findings that affect correctness, security or a stated requirement. Skip style, naming and speculative hardening.

Check:
- Does it do what the task and the brief require? Is each claim of "verified" backed by a check that ran?
- Wire compatibility: anything that differs from the Swift definition.
- Security: unpaired keys refused before any session data; private keys and the paired list stored 0600 and never logged; the plain door unreachable without the development flag; listeners bound as intended; no input injected before a session is authenticated; input from the network validated and bounded.
- Cleanup: nothing left running or created after tests.
- Scope: nothing changed under Sources/, iOSClient/ or Package.swift.

For each finding give: severity (blocker or should-fix), path:line, what is wrong, and the smallest fix. If you find nothing that meets the bar, say so in one line.
```

---

## Appendix B. Minimum content of each verify tier

**T0 static**

- `cargo fmt --all --check`
- `cargo clippy --workspace --all-targets -- -D warnings`
- `cargo test --workspace`
- `cargo check -p sill-host-windows --target x86_64-pc-windows-gnu`. If the target is not installed, print SKIP for this line with the install command, and list it in the NOTES file.

**T1 protocol** (synthetic backend, loopback)

- The default door is TLS. A plain connection is refused unless the development flag is set.
- Pair by code. Restart the host. Reconnect with the pinned key, no code needed.
- An unpaired key is refused in the handshake.
- The source list arrives. Picking a source starts video.
- At least 60 frames arrive and decode as HEVC at the announced size.
- A keyframe request produces a keyframe.
- Input messages of each type are accepted.
- Every kind marked "required" in `PROTOCOL-GAP.md` round-trips against its fixture. Every kind marked "decline" gets the response the Swift host would give.
- An unknown kind is skipped and the session continues.
- Goodbye closes cleanly.

**T2 backend** (nested Hyprland instance)

- The window list matches `hyprctl clients -j`.
- An output capture returns frames of the right size whose pixel colours match a known test pattern, with red and blue the right way round.
- A window capture keeps updating while another window covers it.
- A headless output can be created, sized, used and removed.
- A pointer move lands where `hyprctl cursorpos` says it should.
- A click focuses the intended test window.
- Typed text, including `é`, `€` and `ж`, arrives intact in a test client.
- After the run, monitor and client lists equal the lists from before.

**T3 end to end** (Hyprland backend, loopback, test client)

- Desktop stream: ten seconds of decodable HEVC. Report resolution, encoder, frames per second, and capture-to-encode latency at p50 and p95.
- Window stream: the same, for one window.
- Target: 30 fps at 1080p with a hardware encoder. If the nested instance cannot reach it, report the number and what limits it. Do not lower the target silently.
- A click and a line of typed text sent through the protocol arrive in the test window.
- `avahi-browse -rt _sill._tcp` shows the service with the expected TXT keys.
- Stopping the daemon leaves nothing behind.

**T4 device** (written as `BETA-TEST.md` for Mark)

- The Linux machine appears in the app on the same network.
- Pair by QR, then by typed code on a second attempt after unpairing.
- Stream the desktop. Stream one window. Cover it with another window.
- Tap, drag, scroll, type with the on-screen keyboard and with a hardware keyboard.
- Lock the iPad, unlock, confirm it reconnects.
- Each step says what to capture if it fails: the daemon log, the app's message, the Hyprland version.
