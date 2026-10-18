"""Shared kwinrc / KWin D-Bus helpers for the wlsaturation CLI and GUI."""

from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path

CONFIG = Path.home() / ".config" / "kwinrc"
GROUP = "Effect-wlsaturation"
PLUGIN = "wlsaturation"
GLOBAL_KEY = "Saturation"

MIN_SATURATION = 0.0
MAX_SATURATION = 4.0
IDENTITY = 1.0


def run(cmd: list[str], check: bool = True, timeout: float | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, check=check, text=True, capture_output=True, timeout=timeout)


def kwrite(key: str, value: str) -> None:
    run(
        [
            "kwriteconfig6",
            "--file",
            "kwinrc",
            "--group",
            GROUP,
            "--key",
            key,
            value,
        ]
    )


def kdelete(key: str) -> None:
    run(
        [
            "kwriteconfig6",
            "--file",
            "kwinrc",
            "--group",
            GROUP,
            "--key",
            key,
            "--delete",
        ]
    )


def kread(key: str, default: str = "") -> str:
    result = run(
        [
            "kreadconfig6",
            "--file",
            "kwinrc",
            "--group",
            GROUP,
            "--key",
            key,
            "--default",
            default,
        ],
        check=False,
    )
    return (result.stdout or "").strip()


ANSI = re.compile(r"\x1b\[[0-9;]*m")


def _kscreen_doctor_binary() -> str | None:
    binary = shutil.which("kscreen-doctor")
    if binary:
        return binary
    for candidate in ("/usr/sbin/kscreen-doctor", "/usr/bin/kscreen-doctor"):
        if Path(candidate).exists():
            return candidate
    return None


def outputs_kscreen() -> list[str]:
    binary = _kscreen_doctor_binary()
    if not binary:
        return []
    try:
        text = run([binary, "-o"], check=False, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    text = ANSI.sub("", text or "")
    found: list[str] = []
    for line in text.splitlines():
        match = re.match(r"^Output:\s+\d+\s+(\S+)", line)
        if match:
            found.append(match.group(1))
    return found


def outputs_kwin() -> list[str]:
    """Connector names from the Screens section of KWin's supportInformation."""
    try:
        text = run(
            ["qdbus6", "org.kde.KWin", "/KWin", "org.kde.KWin.supportInformation"],
            check=False,
            timeout=10,
        ).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    lines = (text or "").splitlines()
    found: list[str] = []
    in_screens = False
    for i, line in enumerate(lines):
        # Top-level sections are a title line underlined with '='.
        underlined = i + 1 < len(lines) and re.match(r"^=+\s*$", lines[i + 1])
        if underlined:
            in_screens = line.strip() == "Screens"
            continue
        if not in_screens:
            continue
        match = re.match(r"^\s*Name\s*[:=]\s*(\S+)", line)
        if match and match.group(1) not in found:
            found.append(match.group(1))
    return found


def outputs() -> list[str]:
    """Connector names via kscreen-doctor, falling back to KWin supportInformation."""
    return outputs_kscreen() or outputs_kwin()


def enable_effect() -> None:
    run(
        [
            "kwriteconfig6",
            "--file",
            "kwinrc",
            "--group",
            "Plugins",
            "--key",
            f"{PLUGIN}Enabled",
            "true",
        ]
    )
    run(
        [
            "qdbus6",
            "org.kde.KWin",
            "/Effects",
            "org.kde.kwin.Effects.loadEffect",
            PLUGIN,
        ],
        check=False,
    )


def reconfigure() -> None:
    run(["qdbus6", "org.kde.KWin", "/KWin", "org.kde.KWin.reconfigure"], check=False)
    run(
        [
            "qdbus6",
            "org.kde.KWin",
            "/Effects",
            "org.kde.kwin.Effects.reconfigureEffect",
            PLUGIN,
        ],
        check=False,
    )


def clamp(value: float) -> float:
    return max(MIN_SATURATION, min(MAX_SATURATION, value))


def format_value(value: float) -> str:
    return f"{value:.6g}"


def parse_value(text: str, default: float = IDENTITY) -> float:
    try:
        return clamp(float(text))
    except ValueError:
        return default


def read_global() -> float:
    return parse_value(kread(GLOBAL_KEY, "1.0"))


def read_output(name: str) -> float | None:
    """Per-output override, or None if the key is unset."""
    text = kread(name)
    if not text:
        return None
    try:
        return clamp(float(text))
    except ValueError:
        return None


def set_saturation(value: float, output: str | None = None, enable: bool = True) -> float:
    """Clamp, write the global (output=None) or per-output key, and reconfigure KWin."""
    value = clamp(value)
    if enable:
        enable_effect()
    kwrite(output or GLOBAL_KEY, format_value(value))
    reconfigure()
    return value


def clear_output(output: str) -> None:
    """Remove a per-output override so the output follows the global value."""
    kdelete(output)
    reconfigure()
