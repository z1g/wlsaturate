# wlsaturation

KWin / Plasma **Wayland** replacement for [cybriq/saturation](https://github.com/cybriq/saturation).

X11 tools such as `cmsaturation.pl` write a DRM **color transform matrix (CTM)** onto each CRTC through RandR. On Wayland the compositor is DRM master, so that ioctl path is gone and those tools do nothing. wlsaturation applies the **same 3×3 matrix** inside KWin as an OpenGL effect, then exposes a small CLI that behaves like the old Perl script.

`1.0` is identity (no change). `0.0` is greyscale. Values above `1.0` boost chroma. `1.6` is the amount that matched the old AMD laptop-panel boost.

**Not a hardware CTM.** It is a compositor shader. Plasma / KWin only. Hyprland users should use `hyprvibr` / `hyprland-ctm-control-v1` instead.

---

## Why the X11 tool cannot work on Wayland

On X11, a userspace client can be DRM master (or talk to the X server, which is). `cmsaturation.pl` computed a 3×3 matrix and programmed it with RandR `CTM` / `GAMMA_LUT` properties. The display controller then multiplied every pixel on that CRTC before it hit the panel. That is why it affected the whole output, including fullscreen games that bypassed the compositor.

On Wayland:

- KWin is DRM master.
- Clients cannot open the DRM node for modesetting.
- There is no RandR CTM for a random process to poke.

So saturation has to happen **in the compositor’s paint path**, or via a compositor-specific protocol (Hyprland’s CTM control). This project takes the KWin-effect route so the numbers stay identical to `cmsaturation.pl`.

---

## What it actually does

### Plugin

`wlsaturation.so` is a KWin effect plugin (`OffscreenEffect`):

1. Loads only when KWin is using **OpenGL compositing** (`SaturationEffect::supported()`).
2. Reads `~/.config/kwinrc` group `[Effect-wlsaturation]`.
3. Compiles a fragment shader that multiplies each window’s RGB by the saturation matrix.
4. For every window that is not the desktop wallpaper, if the amount for that window’s output is not `1.0`, it **redirects** the window through an offscreen texture and runs the shader.
5. Runs late in the effect chain (`requestedEffectChainPosition() == 98`) so most other appearance effects have already painted.

Per-output overrides use the **connector name** KWin knows (`eDP-1`, `HDMI-A-1`, …), the same names `kscreen-doctor -o` prints.

If the amount is `1.0` (identity), the window is **not** redirected. That lets KWin keep direct scanout for fullscreen clients when you are not boosting.

### The matrix (same as `cmsaturation.pl`)

For saturation amount `a`:

```
s = (1 - a) / 3
d = s + a

[ d  s  s ]
[ s  d  s ]
[ s  s  d ]
```

Applied as:

```
R' = d*R + s*G + s*B
G' = s*R + d*G + s*B
B' = s*R + s*G + d*B
```

Properties:

| `a` | Result |
|-----|--------|
| `0` | Equal-weight mix of R,G,B → grey |
| `1` | Identity |
| `>1` | Extra chroma (the “AMD vibrance” look) |
| clamp | Code clamps to `[0, 4]` |

The shader un-premultiplies by alpha, applies the matrix, clamps to `[0, 1]`, re-multiplies by alpha, then applies KWin’s `modulation` uniform so opacity/brightness from the compositor still work.

There are two shaders:

- `src/shaders/saturation.frag` — GLSL 1.10-style (`texture2D`, `gl_FragColor`)
- `src/shaders/saturation_core.frag` — `#version 140` core profile

KWin’s `ShaderManager` picks the right one from the Qt resource (`saturation.qrc`).

### Config the CLI writes

`tools/wlsaturation` is a Python 3 helper. It does **not** talk to DRM. It:

1. Enables the plugin: `kwinrc` `[Plugins] wlsaturationEnabled=true`
2. Writes `Saturation` (global) or a connector key (per output) under `[Effect-wlsaturation]`
3. Asks KWin to load/reconfigure the effect over D-Bus (`qdbus6`)

So the value survives logout. Autostart of `wlsaturation 1.6` is optional insurance; kwinrc is the real store.

### Limits (read these)

- **KWin / Plasma only.** Not GNOME, not Sway, not Hyprland.
- **Shader, not CRTC CTM.** Fullscreen direct scanout is blocked **while a boost is active** so the game still gets the effect. At `1.0` the effect unredirects and scanout can return.
- The **desktop wallpaper** window is skipped (`window->isDesktop()`).
- HDR / ICC / Night Color pipelines may not match X11 bit-for-bit. SDR AMD panels should look like the old tool.
- Needs a **logged-in Plasma session** with OpenGL compositing. It cannot run on Gamescope / Steam Game Mode.

---

## Requirements

- KDE Plasma 6 / KWin 6 (Wayland)
- OpenGL compositing (the default)
- CMake ≥ 3.20, C++20 compiler
- Extra CMake Modules 6
- Qt 6 (Core, Gui; Widgets is a CMake find)
- KF6 Config + CoreAddons
- KWin development files (`find_package(KWin)`, link `KWin::kwin`)

Runtime for the CLI: `python3`, `kwriteconfig6`, `kreadconfig6`, `qdbus6`, and `kscreen-doctor` (from KScreen) to list outputs.

---

## Build

Out-of-source CMake. Do **not** ship or copy the `build/` tree.

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build -j"$(nproc)"
sudo cmake --install build
```

That installs:

- `/usr/lib/qt6/plugins/kwin/effects/plugins/wlsaturation.so` (path can vary; ECM’s `kwin/effects/plugins` namespace)
- `/usr/bin/wlsaturation`

Then either log out of Plasma or:

```bash
qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure
```

### Arch / CachyOS

```bash
sudo pacman -S --needed base-devel cmake extra-cmake-modules \
    qt6-base kf6-kconfig kf6-kcoreaddons kwin python kscreen
```

`kwin` on Arch already ships the CMake package `KWin`. `kscreen` gives `kscreen-doctor`. `kf6-kconfig` / Plasma give `kwriteconfig6`. `qt6-tools` is only needed if `qdbus6` is missing (`pacman -S qt6-tools`).

Then the generic `cmake` / `cmake --build` / `cmake --install` block above.

### Debian / Ubuntu (Plasma 6)

You need a Plasma **6** userland (`kwin-dev` that provides `KWinConfig.cmake`). Debian 13+, Ubuntu 25.04+, Kubuntu with Plasma 6, or KDE neon. Plasma 5 `kwin-dev` will not work.

```bash
sudo apt install --no-install-recommends \
    cmake g++ extra-cmake-modules \
    qt6-base-dev qt6-base-private-dev \
    libkf6config-dev libkf6coreaddons-dev \
    kwin-dev \
    python3 plasma-workspace libkscreen-bin
```

`qt6-base-private-dev` is often required because KWin headers pull Qt private includes. `libkscreen-bin` is `kscreen-doctor`. `plasma-workspace` has `kwriteconfig6`. If CMake cannot find Qt6::DBus tools, also install `qt6-tools-dev` / `qdbus-qt6`.

If `find_package(KWin)` still fails:

```bash
dpkg -L kwin-dev | grep -i KWinConfig
```

### Fedora (Kinoite: build in a toolbox/container)

```bash
sudo dnf install cmake gcc-c++ extra-cmake-modules \
    qt6-qtbase-devel \
    kf6-kconfig-devel kf6-kcoreaddons-devel \
    kwin-devel \
    python3 plasma-workspace libkscreen
```

`kwin-devel` provides `cmake(KWin)`. If CMake asks for Qt private headers, add `qt6-qtbase-private-devel`. For `qdbus6`: `qt6-qttools`.

Atomic desktops (Kinoite, Silverblue): build in a toolbox, then overlay or copy the `.so` into the effect plugin directory — you cannot `cmake --install` onto a read-only `/usr` without rpm-ostree.

---

## Use

### CLI (same spirit as `cmsaturation.pl`)

```bash
wlsaturation                  # list outputs and current values
wlsaturation --list           # same
wlsaturation 1.6              # all outputs
wlsaturation HDMI-A-1 1.6     # one connector
wlsaturation HDMI-A-1 1       # reset one output to identity
wlsaturation 1                # reset everything
```

Range: `0.0` … `4.0`. Connector names come from `kscreen-doctor -o` (`Output: N <name>`).

### Desktop Effects GUI

System Settings → Window Management → Desktop Effects → **Wayland Saturation**

Enable it, or from a terminal:

```bash
kwriteconfig6 --file kwinrc --group Plugins --key wlsaturationEnabled true
qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure
```

The GUI toggle only loads the plugin. The **amount** is still the kwinrc keys (or the CLI).

### What lands in `~/.config/kwinrc`

```ini
[Plugins]
wlsaturationEnabled=true

[Effect-wlsaturation]
Saturation=1.6
HDMI-A-1=1.2
```

`Saturation` is the default for every output. Any other key in that group is a per-connector override. After a successful `wlsaturation 1.6`, KWin should restore that value on next Plasma login. No autostart is required.

### Optional autostart

If you want the old “run a command at login” habit:

`~/.config/autostart/wlsaturation.desktop`

```ini
[Desktop Entry]
Type=Application
Name=Wayland Saturation
Exec=wlsaturation 1.6
X-KDE-autostart-phase=2
OnlyShowIn=KDE;
```

Harmless if kwinrc already enabled the effect.

### Check it stuck

```bash
kreadconfig6 --file kwinrc --group Plugins --key wlsaturationEnabled
kreadconfig6 --file kwinrc --group Effect-wlsaturation --key Saturation
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded wlsaturation
```

You want `true`, `1.6` (or whatever you set), and `true`.

---

## Uninstall

```bash
sudo rm -f /usr/bin/wlsaturation
sudo rm -f /usr/lib/qt6/plugins/kwin/effects/plugins/wlsaturation.so
# Debian/Fedora may use /usr/lib/x86_64-linux-gnu/qt6/plugins/... or /usr/lib64/...
```

Then disable and reconfigure:

```bash
kwriteconfig6 --file kwinrc --group Plugins --key wlsaturationEnabled false
qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure
```

If you used `cmake --install`, `sudo cmake --install build` prints an install manifest; `xargs rm` on `build/install_manifest.txt` is cleaner.

---

## Layout

```
CMakeLists.txt
src/main.cpp                 KWIN_EFFECT_FACTORY_SUPPORTED
src/saturationeffect.{h,cpp} OffscreenEffect, config, redirect
src/saturation.qrc
src/shaders/saturation.frag
src/shaders/saturation_core.frag
src/metadata.json            Desktop Effects name / description
tools/wlsaturation           Python CLI
```
