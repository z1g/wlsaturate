# wlsaturate
KWin Wayland effect that restores AMD-style display saturation after X11, using the same 3×3 color matrix as cybriq/saturation.
This is AI Generated slop created to replace cmdemo and cmsaturation.pl used to add an equivelent of NVIDIA's Digital Vibrance for AMD Cards in Linux.

What it is
wlsaturation is a KWin 6 effect plus a Python CLI. It is the Wayland stand-in for cybriq/saturation / cmsaturation.pl.

On X11 that Perl script wrote a DRM color transform matrix (CTM) onto each CRTC through RandR. The display hardware then multiplied every pixel, including fullscreen games that never touched the compositor.

On Wayland KWin is DRM master. A normal process cannot program CRTC CTM. So this project applies the same 3×3 matrix in KWin’s OpenGL paint path instead of on the CRTC.

1.0 = no change. 0.0 = grey. 1.6 = the boost you used on the laptop panel. Values are clamped to 0…4.

It is not a hardware CTM. Plasma / KWin only. Hyprland people want hyprvibr / hyprland-ctm-control-v1.

How the effect works
wlsaturation.so is a KWin OffscreenEffect:

Loads only if KWin is using OpenGL compositing.
Reads ~/.config/kwinrc group [Effect-wlsaturation].
Compiles a fragment shader that multiplies RGB by the saturation matrix.
For each window that is not the desktop wallpaper: if that output’s amount is not 1.0, redirect the window to an offscreen texture and run the shader.
Runs late in the chain (requestedEffectChainPosition() == 98).
At 1.0 it unredirects, so fullscreen direct scanout can come back. While you are boosting, scanout is blocked on purpose so games still get the colour.

Per-output keys are KWin connector names (eDP-1, HDMI-A-1), the same names kscreen-doctor -o prints.

The CLI does not talk to DRM. It writes kwinrc, sets wlsaturationEnabled=true, then pokes KWin over D-Bus (loadEffect / reconfigure). That is why a value survives logout.

The matrix (same as cmsaturation.pl)
For amount a:

s = (1 - a) / 3
d = s + a

[ d  s  s ]
[ s  d  s ]
[ s  s  d ]
The shader un-premultiplies alpha, applies that, clamps to [0,1], re-multiplies alpha, then applies KWin’s modulation uniform.

Limits
KWin / Plasma only. Not GNOME, Sway, Gamescope, or Steam Game Mode.
Shader, not CRTC CTM.
Wallpaper window is skipped.
HDR / ICC / Night Color may not match X11 bit-for-bit. SDR AMD panels should.
Build
Need Plasma 6, CMake ≥ 3.20, C++20, ECM 6, Qt 6, KF6 Config + CoreAddons, and KWin development files (find_package(KWin) / KWin::kwin). Do not copy or ship build/.

cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr
cmake --build build -j"$(nproc)"
sudo cmake --install build
qdbus6 org.kde.KWin /KWin org.kde.KWin.reconfigure
Installs the plugin under Qt’s kwin/effects/plugins dir and /usr/bin/wlsaturation.

Arch / CachyOS
sudo pacman -S --needed base-devel cmake extra-cmake-modules \
    qt6-base kf6-kconfig kf6-kcoreaddons kwin python kscreen
If qdbus6 is missing: sudo pacman -S qt6-tools. Then the cmake block above.

Debian / Ubuntu (Plasma 6 only)
Plasma 5 kwin-dev will not work. You want Debian 13+, Ubuntu 25.04+, Kubuntu with Plasma 6, or neon.

sudo apt install --no-install-recommends \
    cmake g++ extra-cmake-modules \
    qt6-base-dev qt6-base-private-dev \
    libkf6config-dev libkf6coreaddons-dev \
    kwin-dev \
    python3 plasma-workspace libkscreen-bin
qt6-base-private-dev is often required because KWin headers pull Qt private includes. libkscreen-bin is kscreen-doctor. If CMake still cannot find KWin: dpkg -L kwin-dev | grep -i KWinConfig.

Fedora
sudo dnf install cmake gcc-c++ extra-cmake-modules \
    qt6-qtbase-devel \
    kf6-kconfig-devel kf6-kcoreaddons-devel \
    kwin-devel \
    python3 plasma-workspace libkscreen
kwin-devel provides cmake(KWin). Add qt6-qtbase-private-devel / qt6-qttools if CMake or qdbus6 complain. On Kinoite/Silverblue, build in a toolbox — you cannot install onto a read-only /usr without rpm-ostree.

Use
wlsaturation                  # list outputs and values
wlsaturation 1.6              # all outputs
wlsaturation HDMI-A-1 1.6     # one connector
wlsaturation HDMI-A-1 1       # reset one
wlsaturation 1                # reset all
GUI: System Settings → Window Management → Desktop Effects → Wayland Saturation. That only loads the plugin; the amount is still kwinrc / the CLI.

What gets written:

[Plugins]
wlsaturationEnabled=true

[Effect-wlsaturation]
Saturation=1.6
HDMI-A-1=1.2
Saturation is the default. Any other key in that group is a per-connector override. After one successful wlsaturation 1.6, login should restore it. Autostart is optional:

# ~/.config/autostart/wlsaturation.desktop
[Desktop Entry]
Type=Application
Name=Wayland Saturation
Exec=wlsaturation 1.6
X-KDE-autostart-phase=2
OnlyShowIn=KDE;
Check:

kreadconfig6 --file kwinrc --group Plugins --key wlsaturationEnabled
kreadconfig6 --file kwinrc --group Effect-wlsaturation --key Saturation
qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.isEffectLoaded wlsaturation
