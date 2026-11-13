# Third-party code and references

Checked on 2026-11-13. "Read for code" means its license allows porting with attribution;
anything else is read for behaviour only and the code written fresh.

## Imported

| What | From | License | Attribution |
|---|---|---|---|
| `hosts/` (four crates, three NOTES files) | Saffsanity/sill pull request 128, head `173843b`, branch `Aileuxe/sill:mac-client`, commit `6d7419f` by Alexander Deutsch | Apache-2.0 (`hosts/Cargo.toml`, `license = "Apache-2.0"`; contributed to an Apache-2.0 repository) | The import commit keeps him as author. The folder has no LICENSE file and no file headers: the root `LICENSE` covers it, and M1 adds a `hosts/NOTICE` naming the origin. Files this work changes get a line saying so. |

Not imported from that pull request: `MacClient/` and its edits to `iOSClient/` (the Mac
Viewer). It changes nothing under `Scripts/`.

## References

| Project | Commit read | License | Use |
|---|---|---|---|
| Saffsanity/sill (upstream) | `bf69067` | Apache-2.0, Copyright 2026 Noah Saffer | The specification. Its `NOTICE`-style credit goes in `hosts/NOTICE`. |
| afds/sill-linux | `18218cc` | Apache-2.0, with a `NOTICE` (Copyright 2026 Deniss Afonin) | Read for code. Rust, the same rustls and ring stack, and the only host with a dated run against the App Store app. Any port of its code is credited in `hosts/NOTICE`. |
| NateHag/Sill-Viewer, `linux-host/` | `82179a7` | Apache-2.0 at the repository root, no copyright line; `linux-host/` has no license of its own, so the root one covers it | Read for code. It ships a prebuilt binary, `linux-host/sill_linux/vkenc/sill-vkenc`: never run it. |
| any1/wayvnc | `1d417b5` | ISC | Read for code (technique: screencopy, virtual input). |
| MuNeNICK/hypr-rdp | not cloned | MIT according to its README; the LICENSE file itself was not read | Behaviour only until the file is read. Its headless sizing uses `hyprctl keyword`, which Hyprland refuses under a Lua configuration (seen on 0.56.2). |
| atx/wtype | not cloned | MIT (to confirm when cloned) | Technique for typing text through a temporary keymap. |
| hyprwm/Hyprland, hyprland-protocols | web | BSD-3-Clause | Protocol XML and behaviour. |

## Crates ruled out by license

| Crate | License | Instead |
|---|---|---|
| `wayland-protocols-hyprland` 1.2.0 | LGPL-3.0-only | Not used. Capture goes through `ext-image-copy-capture-v1`. The one Hyprland-only protocol wanted, `hyprland-toplevel-mapping-v1` (a capture handle's window address), gets bindings generated from hyprland-protocols' BSD-3 XML. |
| `hyprland` (hyprland-rs) 0.3.13 | GPL-3.0-or-later | A small IPC client of our own. It also predates the Lua configuration and the 0.57 IPC changes. |

## Crates the backend expects to add

All MIT or MIT/Apache: `wayland-client` 0.31, `wayland-protocols` 0.32 (staging, for the
`ext-*` protocols), `wayland-protocols-wlr` 0.3, `xkeysym` 0.2, `qrcode` 0.14. The keymap is
generated as text, so nothing links libxkbcommon. FFmpeg and x265 run as a subprocess and are
never linked.

In the imported lock file, three entries need their license confirmed in M1 with
`cargo metadata`: `r-efi` (MIT OR Apache-2.0 OR LGPL-2.1+, a permissive choice exists), `zmij`
and a second `syn`.

## Naming

Apache-2.0 grants no trademark rights. User-facing text calls this an unofficial host for the
Sill app; the package name is Mark's decision (`DECISIONS.md`).
