#!/usr/bin/env bash
# Read-only probe of the machine the Hyprland host will run on (Milestone 0).
# Run it in a terminal inside the Hyprland session, as your own user, never with sudo:
#     bash docs/hyprland-host/probe.sh 2>&1 | tee /tmp/sill-probe.txt
# Part A only reads. Part B starts a second, nested Hyprland (a window, about ten
# seconds) with an empty configuration, tries a headless output inside that instance
# only, and closes it. Skip part B with:  SILL_PROBE_NO_NESTED=1 bash probe.sh
# It prints no window titles and no file contents from your configuration.
set +e
sec() { printf '\n## %s\n' "$*"; }
have() { for t in "$@"; do printf '%-26s %s\n' "$t" "$(command -v "$t" 2>/dev/null || echo MISSING)"; done; }

sec system
uname -sr; grep -E '^(NAME|BUILD_ID)=' /etc/os-release
echo "session: ${XDG_SESSION_TYPE:-?}  WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-unset}  signature set: $([ -n "$HYPRLAND_INSTANCE_SIGNATURE" ] && echo yes || echo no)"

sec omarchy
omarchy-version 2>/dev/null || cat ~/.local/share/omarchy/version 2>/dev/null || echo "no omarchy-version"
pacman -Q 2>/dev/null | grep -i -E '^(omarchy|quickshell)' | head -8

sec hyprland
hyprctl version 2>&1 | head -12
pacman -Q hyprland aquamarine hyprland-protocols xdg-desktop-portal-hyprland hyprland-guiutils hyprutils 2>&1
echo "-- instances"; hyprctl instances 2>&1 | grep -E 'instance|wl socket' | sed -E 's/(instance [0-9a-f]{8})[0-9a-f_]*/\1…/'
echo "-- monitors"; hyprctl monitors 2>&1 | grep -E '^Monitor|^[[:space:]]+[0-9]+x[0-9]+@|scale:|transform:'
echo "-- clients: $(hyprctl -j clients 2>/dev/null | grep -c '"address"') windows; one address: $(hyprctl -j clients 2>/dev/null | grep -m1 -o '"address": *"[^"]*"')"
echo "-- enforce_permissions"; hyprctl getoption ecosystem:enforce_permissions 2>&1 | head -3
echo "-- locked"; hyprctl locked 2>&1 | head -2
echo "-- keyboard"; hyprctl getoption input:kb_layout 2>&1 | head -2; hyprctl -j devices 2>/dev/null | grep -E '"(layout|variant|active_keymap)"' | sort -u | head -6
echo "-- config files"; ls ~/.config/hypr 2>/dev/null | head -30
echo "-- files that mention permissions"; grep -rl -E 'hl\.permission|enforce_permissions|^permission' ~/.config/hypr ~/.local/share/omarchy/default/hypr 2>/dev/null | head

sec "wayland globals (live session)"
if command -v wayland-info >/dev/null; then
  wayland-info 2>/dev/null | grep -oE "interface: '[a-z0-9_]+', +version: +[0-9]+" | sed -E "s/interface: '([a-z0-9_]+)', +version: +/\1 v/" | sort -u
else echo "wayland-info MISSING (package wayland-utils)"; fi

sec gpu
lspci -k 2>/dev/null | grep -A2 -E 'VGA|3D controller|Display controller' | grep -v '^--'
ls /dev/dri 2>&1 | tr '\n' ' '; echo
vainfo 2>&1 | grep -i -E 'driver version|HEVC|error|not found' | head -12
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader 2>&1 | head -2

sec ffmpeg
ffmpeg -version 2>&1 | head -1
ffmpeg -hide_banner -encoders 2>/dev/null | grep -i -E 'hevc|265'

sec toolchain
have cargo rustc rustup x86_64-w64-mingw32-gcc cc python3 makepkg docker claude gh
cargo --version 2>&1; rustup show active-toolchain 2>&1 | head -1; rustup target list --installed 2>&1 | tr '\n' ' '; echo
python3 --version 2>&1; ls -l /usr/sbin/lsof /usr/bin/openssl /bin/ps 2>&1; claude --version 2>&1 | head -1

sec "avahi and firewall"
systemctl is-active avahi-daemon 2>&1; systemctl is-enabled avahi-daemon 2>&1
pacman -Q avahi nss-mdns ufw 2>&1
echo "ufw: $(systemctl is-active ufw 2>&1) / $(systemctl is-enabled ufw 2>&1)"

sec "test tools"
have wayland-info avahi-browse avahi-publish wtype wev foot wl-copy wl-paste notify-send qrencode ffprobe lsof

if [ -z "$SILL_PROBE_NO_NESTED" ] && command -v Hyprland >/dev/null && [ -n "$XDG_RUNTIME_DIR" ]; then
  sec "nested Hyprland (a window opens for about ten seconds)"
  T=$(mktemp -d); : > "$T/hyprland.lua"
  before=$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | sort)
  Hyprland --config "$T/hyprland.lua" >"$T/log" 2>&1 & P=$!
  trap 'kill $P 2>/dev/null; rm -rf "$T"' EXIT
  sig=""; for i in 1 2 3 4 5 6 7 8 9 10; do sleep 1
    sig=$(comm -13 <(echo "$before") <(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | sort) | head -1)
    [ -n "$sig" ] && [ -S "$XDG_RUNTIME_DIR/hypr/$sig/.socket.sock" ] && break; done
  if [ -z "$sig" ] || [ "$sig" = "$HYPRLAND_INSTANCE_SIGNATURE" ]; then
    echo "NO NESTED INSTANCE after 10 s"; tail -15 "$T/log"
  else
    h() { hyprctl -i "$sig" "$@" 2>&1; }
    echo "nested instance started after ${i}s; sockets: $(ls -A "$XDG_RUNTIME_DIR/hypr/$sig" | tr '\n' ' ')"
    ws=$(hyprctl instances 2>/dev/null | grep -A4 "$sig" | grep -oE 'wayland-[0-9]+' | head -1); echo "its wayland socket: ${ws:-?}"
    echo "-- monitors"; h monitors | grep -E '^Monitor|^[[:space:]]+[0-9]+x[0-9]+@'
    echo "-- output create headless"; h output create headless SILLPROBE; sleep 1
    echo "-- size by eval"; h eval 'hl.monitor({ output = "SILLPROBE", mode = "1280x800@60", position = "auto", scale = 1 })'; sleep 1
    h monitors | grep -A1 -E '^Monitor SILLPROBE'
    echo "-- size by keyword (expected to fail on 0.57)"; h keyword monitor SILLPROBE,1024x768@60,auto,1; sleep 1
    h monitors | grep -A1 -E '^Monitor SILLPROBE'
    if [ -n "$ws" ] && command -v wayland-info >/dev/null; then
      echo "-- nested globals of interest"
      WAYLAND_DISPLAY=$ws wayland-info 2>/dev/null | grep -oE "interface: '[a-z0-9_]+'" | grep -E 'image_c|foreign_toplevel|toplevel_export|screencopy|virtual_|data_control|lock' | sort -u
    fi
    echo "-- output remove"; h output remove SILLPROBE; sleep 1
    h monitors | grep -E '^Monitor'
    echo "-- exit"; h dispatch exit; sleep 1
  fi
  kill $P 2>/dev/null; wait $P 2>/dev/null; trap - EXIT
  echo "-- last log lines"; grep -i -E 'error|crit|allocator|backend' "$T/log" | tail -8; rm -rf "$T"
  echo "-- instances left: $(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | wc -l) (before: $(echo "$before" | grep -c .))"
fi
sec done
