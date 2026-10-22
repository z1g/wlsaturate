# wlsaturation

This is AI generated slop.  It is created for the need to replace cmdemo and cmsaturation.pl to apply NVIDIA's equivalent of digital vibrance for AMD cards in a Wayland KDE Plasma session.  This will not work with other desktop environments or window managers.  I am only putting this here as it may be useful for others looking for the same functionality.

KWin / Plasma **Wayland** replacement for [cybriq/saturation](https://github.com/cybriq/saturation) (`cmdemo` + `cmsaturation.pl`).

The public GitHub repo is **[z1g/wlsaturate](https://github.com/z1g/wlsaturate)**. The KWin plugin, CLI, and GUI are still named **wlsaturation**.

`1.0` is identity (no change). `0.0` is greyscale. Values above `1.0` boost chroma. `1.6` is the amount that matched the old AMD laptop-panel boost (NVIDIA “Digital Vibrance” for AMD, without NVIDIA).

**Not a hardware CTM.** It is a compositor shader. Plasma / KWin only. Hyprland users should use `hyprvibr` / `hyprland-ctm-control-v1` instead.

---

## What it does

wlsaturation restores **display saturation / vibrance** after you leave X11.

On X11, AMD (and others) could program a 3×3 **color transform matrix (CTM)** on each CRTC. NVIDIA called the same idea Digital Vibrance. `cmsaturation.pl` wrote that matrix through RandR. The display controller then multiplied every pixel on that output, including fullscreen games that never touched the compositor.

On Wayland that path is gone. This project:

1. Loads a **KWin 6 effect plugin** (`wlsaturation.so`).
2. Applies the **same 3×3 matrix as `cmsaturation.pl`** in a fragment shader while KWin paints.
3. Stores the amount in `~/.config/kwinrc` so it survives logout.
4. Ships a **CLI** (`wlsaturation`) in the spirit of the old Perl script.
5. Ships a **PyQt6 GUI** (`wlsaturation-gui`) with a slider per display.


---

## Why it has to work this way

On X11, a userspace client can be DRM master (or talk to the X server, which is). `cmsaturation.pl` computed a 3×3 matrix and programmed it with RandR `CTM` / `GAMMA_LUT`. That is why it affected the whole output.

On Wayland:

- **KWin is DRM master.**
- Clients cannot open the DRM node for modesetting (`EACCES` if you try to write the CRTC `CTM` blob yourself).
- There is no RandR CTM for a random process to poke.
- KWin’s own `WindowPaintData::setSaturation` / `multiplySaturation` is **desaturate-only** (`[0, 1]`). It cannot boost.

So saturation has to happen **in the compositor’s paint path**, or via a compositor-specific protocol (Hyprland’s CTM control). This project takes the KWin-effect route so the numbers stay identical to `cmsaturation.pl`.

Do **not** rewrite [cybriq/saturation](https://github.com/cybriq/saturation) for Wayland, and do **not** write a raw `libdrm` CTM tool while KWin holds the device. Those cannot work.

---

## How it actually works

### Plugin

`wlsaturation.so` is a KWin `OffscreenEffect`:

1. Loads only when KWin is using **OpenGL compositing** (`SaturationEffect::supported()`).
2. Reads `~/.config/kwinrc` group `[Effect-wlsaturation]`.
3. Compiles a fragment shader that multiplies each window’s RGB by the saturation matrix.
4. If the amount for that window’s output is not `1.0`, it **redirects** the window through an offscreen texture and runs the shader.
5. Runs late in the effect chain (`requestedEffectChainPosition() == 98`) so most other appearance effects have already painted.

Per-output overrides use the **connector name** KWin knows (`eDP-1`, `HDMI-A-1`, `DP-1`, …), the same names `kscreen-doctor -o` prints. DP-to-HDMI adapters still enumerate as `DP-*`, not `HDMI-A-*`.

If the amount is `1.0` (identity), the window is **not** redirected. That lets KWin keep direct scanout for fullscreen clients when you are not boosting. While a boost is active, scanout is blocked **on purpose** so fullscreen games still get the matrix.

The desktop wallpaper is included (closer to a CRTC CTM than skipping `isDesktop()`).

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

| `a`   | Result                                 |
|-------|----------------------------------------|
| `0`   | Equal-weight mix of R,G,B → grey       |
| `1`   | Identity                               |
| `>1`  | Extra chroma (the “AMD vibrance” look) |
| clamp | Code clamps to `[0, 4]`                |

The shader un-premultiplies by alpha, converts to linear (gamma 2.2), applies the matrix, converts back, re-multiplies by alpha, then applies KWin’s `modulation` uniform. Boosted primaries are **not** hard-clipped to `[0, 1]` (the framebuffer still clips at the end). That is closer to CRTC CTM, not identical. HDR / ICC / Night Color can diverge; SDR AMD panels should look like the old tool.

There are two shaders:

- `src/shaders/saturation.frag` — GLSL 1.40 / GLES 3 (`in` / `out` / `texture` / `fragColor`, **no `#version`**; KWin prepends it)
- `src/shaders/saturation_core.frag` — `#version 140` core profile (Plasma 6.7 desktop GL)

Plasma 6.8 KWin is GLES-only (`#version 300 es`). The old GLSL 1.10 `varying` / `texture2D` / `gl_FragColor` shader fails with `illegal use of reserved word varying`. The CLI can still “succeed” in that case because it only writes kwinrc — the picture will not change until the shader compiles.

KWin’s `ShaderManager` loads `saturation.frag` from the Qt resource (`saturation.qrc`).

### CLI and GUI

`tools/wlsaturation` and `tools/wlsaturation-gui` share `tools/wlsaturation_lib.py`. They do **not** talk to DRM. They:

1. Enable the plugin: `kwinrc` `[Plugins] wlsaturationEnabled=true`
2. Write `Saturation` (global) or a connector key (per output) under `[Effect-wlsaturation]`
3. Ask KWin to load/reconfigure the effect over D-Bus (`qdbus6`)

Outputs are listed with `kscreen-doctor -o` (ANSI stripped). If that binary is missing, aborts, or returns no names, names come from `qdbus6 org.kde.KWin /KWin org.kde.KWin.supportInformation` (`Screens` → `Name=`). Empty kscreen-doctor is **not** “no displays.”

kwinrc is the real store. Autostart of `wlsaturation 1.6` is optional insurance.

### Limits

- **KWin / Plasma 6 only.** Not GNOME, not Sway, not Hyprland, not Gamescope / Steam Game Mode.
- **Shader, not CRTC CTM.** Fullscreen direct scanout is blocked while a boost is active.
- Needs a **logged-in Plasma session** with OpenGL compositing.
- Rebuild against the **installed** KWin headers after a KWin ABI bump. Copying `wlsaturation.so` between machines or Plasma versions will fail to load.
- Do **not** copy or ship a `build/` directory.

---

## Requirements

- KDE Plasma 6 / KWin 6 (Wayland)
- OpenGL compositing (the default)
- CMake ≥ 3.20, C++20 compiler
- Extra CMake Modules 6
- Qt 6 (Core, Gui; Widgets is a CMake find)
- KF6 Config + CoreAddons
- KWin development files (`find_package(KWin)`, link `KWin::kwin`)
- Vulkan headers (KWin’s CMake package often pulls them in)

Runtime for the CLI: `python3`, `kwriteconfig6`, `kreadconfig6`, `qdbus6`, and `kscreen-doctor` (from KScreen).

Runtime for the GUI: PyQt6 for **system** `/usr/bin/python3` (the GUI shebang is `/usr/bin/python3` on purpose — do not launch it with a venv/`env` Python that has no PyQt6).

---

## Build

Out-of-source CMake. **Rebuild on each machine.** Do **not** copy `build/` between hosts (KWin ABI).

### One-liner (this tree)

```bash
chmod +x build.sh tools/wlsaturation tools/wlsaturation-gui
./build.sh --install --reload
```

`build.sh` writes objects to `~/.cache/wlsaturation-build` by default so a synced folder does not pick up object files. Override with `BUILD_DIR=./build` if you want a local `build/` (still do not upload it).

```
./build.sh                         # configure + compile only
./build.sh --install --reload      # install to /usr and reload the KWin effect
./build.sh --menu                  # user Kickoff entry, no sudo
./build.sh --deps --install --reload   # Arch/CachyOS: missing packages only, then install
```

`--deps` is **Arch/CachyOS pacman only**, and it installs **missing** packages. It will not upgrade an already-installed `kwin`. Never `pacman -S kwin` just to get headers while the rest of Plasma is an older release (that is how a 6.8 `kwin` lands on 6.7 and `kwin_wayland` dies with a missing `KGlobalAccelD::axisTriggered` symbol / black SDDM greeter).

### Generic CMake (any distro)

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build -j"$(nproc)"
sudo cmake --install build
```

That installs:

- `wlsaturation.so` under ECM’s `kwin/effects/plugins` namespace  
  (often `/usr/lib/qt6/plugins/kwin/effects/plugins/`; Debian may use `/usr/lib/x86_64-linux-gnu/qt6/plugins/…`; Fedora `/usr/lib64/…`)
- `/usr/bin/wlsaturation`
- `/usr/bin/wlsaturation-gui`
- `/usr/share/wlsaturation/wlsaturation_lib.py`
- `/usr/share/applications/wlsaturation-gui.desktop`

Then either log out of Plasma or:

```bash
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.unloadEffect wlsaturation || true
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadEffect wlsaturation
```

A new `.so` with a changed shader is **not** enough if `kwin_wayland` is still the same PID. Qt keeps the first `Q_INIT_RESOURCE(saturation)` for the process, so a reload can keep compiling the old GLSL. Log out of Plasma once after a shader change. The plugin destructor calls `Q_CLEANUP_RESOURCE(saturation)` so later reloads can pick up a new `.so`.

KWin plugin `metadata.json` must **not** set `KPlugin.Id` (KWin warns; pluginId comes from the `.so` name).

---

### Arch / CachyOS

Package names are `kconfig` and `kcoreaddons` (group `kf6`), **not** Fedora’s `kf6-kconfig`.

```bash
sudo pacman -S --needed base-devel cmake extra-cmake-modules vulkan-headers \
    qt6-base qt6-tools kconfig kcoreaddons kwin python kscreen python-pyqt6
```

Or, from this tree, only the packages that are actually missing:

```bash
./build.sh --deps --install --reload
```

- `kwin` already ships the CMake package `KWin`. Compile against the kwin **already on the desktop**.
- `kscreen` gives `kscreen-doctor` (sometimes `/usr/sbin/kscreen-doctor`).
- `kconfig` / Plasma give `kwriteconfig6` / `kreadconfig6`.
- `qt6-tools` provides `qdbus6`.
- `python-pyqt6` is the GUI runtime for `/usr/bin/python3`.
- `vulkan-headers` is a KWin CMake dependency on this distro, not a product feature.

Then the generic `cmake` block, or `./build.sh --install --reload`.

---

### Fedora (Kinoite: build in a toolbox)

Fedora KF6 devel packages are `kf6-kconfig-devel` / `kf6-kcoreaddons-devel`. Those names will fail on Arch.

```bash
sudo dnf install cmake gcc-c++ extra-cmake-modules vulkan-headers \
    qt6-qtbase-devel qt6-qttools \
    kf6-kconfig-devel kf6-kcoreaddons-devel \
    kwin-devel \
    python3 python3-pyqt6 plasma-workspace libkscreen
```

- `kwin-devel` provides `cmake(KWin)`.
- If CMake asks for Qt private headers, add `qt6-qtbase-private-devel`.
- `qt6-qttools` is `qdbus6`.
- `python3-pyqt6` is the GUI.
- `libkscreen` is `kscreen-doctor`.
- `plasma-workspace` has `kwriteconfig6`.

Then:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build -j"$(nproc)"
sudo cmake --install build
```

Atomic desktops (Kinoite, Silverblue, Kinoite-based): build in a **toolbox**, then overlay or copy the `.so` into the effect plugin directory. You cannot `cmake --install` onto a read-only `/usr` without rpm-ostree.

`./build.sh --deps` will not work here (pacman only). Use `dnf` as above, then `./build.sh --install --reload` if `/usr` is writable.

---

### Debian / Ubuntu (Plasma 6)

You need a Plasma **6** userland (`kwin-dev` that provides `KWinConfig.cmake`). Debian 13+, Ubuntu 25.04+, Kubuntu with Plasma 6, or KDE neon. Plasma 5 `kwin-dev` will not work.

```bash
sudo apt install --no-install-recommends \
    cmake g++ extra-cmake-modules \
    qt6-base-dev qt6-base-private-dev qt6-tools-dev qdbus-qt6 \
    libkf6config-dev libkf6coreaddons-dev \
    kwin-dev \
    libvulkan-dev \
    python3 python3-pyqt6 plasma-workspace libkscreen-bin
```

- `qt6-base-private-dev` is often required because KWin headers pull Qt private includes.
- `libkscreen-bin` is `kscreen-doctor`.
- `plasma-workspace` has `kwriteconfig6`.
- `qt6-tools-dev` / `qdbus-qt6` if CMake or the CLI cannot find Qt6 D-Bus tools / `qdbus6`.
- `python3-pyqt6` is the GUI.
- `libvulkan-dev` if `find_package(KWin)` wants Vulkan headers.

If `find_package(KWin)` still fails:

```bash
dpkg -L kwin-dev | grep -i KWinConfig
```

Then the generic `cmake` block. `./build.sh --deps` will not work here (pacman only). Use `apt` as above, then `./build.sh --install --reload`.

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

Range: `0.0` … `4.0`. From the source tree: `./tools/wlsaturation`.

### GUI

```bash
wlsaturation-gui              # installed
./tools/wlsaturation-gui      # from this tree
```

A small window with an **All outputs** row (the global `Saturation` key, same as `wlsaturation 1.6`) and one row per connector. Each row has a slider and a spinbox (0.00–4.00, step 0.05). Changes apply live: written to kwinrc and KWin reconfigured on slider release, debounced while dragging.

- **Reset** sets that row to `1.0`.
- **Global** removes the per-output override so the output follows the global value again. Italic names are currently following global.

After `cmake --install`, Plasma lists it in the application menu as **wlsaturation** (`data/wlsaturation-gui.desktop`).

User-only Kickoff entry (no sudo, runs this folder’s GUI):

```bash
./build.sh --menu
```

That writes `~/.local/share/applications/wlsaturation-gui.desktop` with an absolute `Exec`. Do not use both `--menu` and `--install` unless you want the user file to override `/usr`.

### Desktop Effects

System Settings → Window Management → Desktop Effects → **Wayland Saturation**

Enable it, or from a terminal:

```bash
kwriteconfig6 --file kwinrc --group Plugins --key wlsaturationEnabled true
qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure
```

That toggle only loads the plugin. The **amount** is still the kwinrc keys (or the CLI / GUI).

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

On KWin 6.7, `loadedEffects` / `listOfEffects` are D-Bus **properties**. `loadEffect` / `isEffectLoaded` are still methods. `listOfEffects` can still show `wlsaturation` while `loadEffect` returns false after an ABI mismatch — rebuild against current kwin headers.

If the CLI prints values but the picture is unchanged, the shader failed to compile (journal: `illegal use of reserved word varying` / `wlsaturation: failed to compile saturation shader`). That is a rebuild + Plasma logout problem, not a kwinrc problem.

---

## Uninstall

```bash
sudo rm -f /usr/bin/wlsaturation /usr/bin/wlsaturation-gui
sudo rm -rf /usr/share/wlsaturation
sudo rm -f /usr/share/applications/wlsaturation-gui.desktop
sudo rm -f /usr/lib/qt6/plugins/kwin/effects/plugins/wlsaturation.so
# Debian/Fedora may use /usr/lib/x86_64-linux-gnu/qt6/plugins/... or /usr/lib64/...
```

Then disable and reconfigure:

```bash
kwriteconfig6 --file kwinrc --group Plugins --key wlsaturationEnabled false
qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure
```

If you used `cmake --install`, `build/install_manifest.txt` (or `~/.cache/wlsaturation-build/install_manifest.txt`) plus `xargs rm` is cleaner.

Remove a user Kickoff entry with:

```bash
rm -f ~/.local/share/applications/wlsaturation-gui.desktop
```

---

## Layout

```
CMakeLists.txt
LICENSE                      GPL-3.0 (same as github.com/z1g/wlsaturate)
README.md
build.sh                     Arch-aware helper; cmake on any distro
how_to_build.txt             short cheat sheet
data/wlsaturation-gui.desktop
src/main.cpp                 KWIN_EFFECT_FACTORY_SUPPORTED
src/saturationeffect.{h,cpp} OffscreenEffect, config, redirect
src/saturation.qrc
src/shaders/saturation.frag
src/shaders/saturation_core.frag
src/metadata.json            Desktop Effects name / description
tools/wlsaturation           Python CLI
tools/wlsaturation-gui       PyQt6 GUI
tools/wlsaturation_lib.py    kwinrc / D-Bus helpers shared by CLI and GUI
```

