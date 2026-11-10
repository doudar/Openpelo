#!/usr/bin/env python3
"""Opt-in ADB wallpaper diagnostics/repair for OpenPelo issue #70.

Python 3.10+, standard library only. Read-only unless --apply or --open-picker
is supplied. Never removes device administrators, changes provisioning, roots
Android, or modifies unrelated restrictions. See docs/wallpaper-troubleshooting.md.
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import re
import subprocess
import sys
from typing import Callable

WALLPAPER_KEYS = ("no_set_wallpaper", "no_wallpaper")
ERROR_OUTPUT = re.compile(
    r"(?im)^\s*(?:error\b|failure\b|unknown command\b|permission denial\b|permission denied\b)"
    r"|\bSecurityException\b|Exception occurred while executing"
)
USER_HEADER = re.compile(r"(?m)^([ \t]*)UserInfo\{0:.*:([0-9a-fA-F]+)\}[^\n]*$")


class RepairError(RuntimeError):
    """An unsupported or unsafe-to-continue device state."""


class Adb:
    def __init__(self, executable: str = "adb", serial: str | None = None,
                 runner: Callable = subprocess.run):
        self.executable = executable
        self.serial = serial
        self.runner = runner

    def run(self, *args: str, targeted: bool = True) -> str:
        if targeted and not self.serial:
            raise RepairError("Select an authorized device before running commands.")
        command = [self.executable]
        if targeted:
            command += ["-s", self.serial]
        command += list(args)
        try:
            result = self.runner(command, capture_output=True, text=True,
                                 encoding="utf-8", errors="replace", timeout=20)
        except (OSError, subprocess.TimeoutExpired) as error:
            raise RepairError(f"ADB command failed: {error}") from error
        output = "\n".join(part for part in (result.stdout, result.stderr) if part).strip()
        if result.returncode or ERROR_OUTPUT.search(output):
            raise RepairError(f"ADB {' '.join(args)} failed: {output or result.returncode}")
        return result.stdout.strip()

    def select_device(self) -> None:
        output = self.run("devices", targeted=False)
        devices = {}
        for line in output.splitlines():
            parts = line.split()
            if len(parts) >= 2 and not line.startswith("List of devices attached"):
                devices[parts[0]] = parts[1]
        if self.serial:
            if devices.get(self.serial) != "device":
                raise RepairError("The selected device is missing, offline, or unauthorized.")
        elif len(devices) == 1 and next(iter(devices.values())) == "device":
            self.serial = next(iter(devices))
        else:
            raise RepairError("Connect one authorized device, or select it with --serial.")

    def require_owner_user(self) -> None:
        current = self.run("shell", "am", "get-current-user")
        if current != "0":
            raise RepairError("Repair requires active Android user 0; user detection was not 0. "
                              "No fallback to a guessed user is allowed.")


def restriction_section(block: str, heading: str) -> frozenset[str] | None:
    """Parse AOSP indented dumps; unknown/null is not proof of an empty policy."""
    lines = block.splitlines()
    matches = [i for i, line in enumerate(lines) if line.strip() == heading]
    if len(matches) != 1:
        return None
    start = matches[0]
    indent = len(lines[start]) - len(lines[start].lstrip())
    entries = []
    for line in lines[start + 1:]:
        if not line.strip():
            continue
        if len(line) - len(line.lstrip()) <= indent:
            break
        entries.append(line.strip())
    if entries == ["none"]:
        return frozenset()
    if not entries or "null" in entries or "none" in entries:
        return None
    enabled = set()
    for entry in entries:
        match = re.fullmatch(r"([a-z][a-z0-9_]*)(?:=(true|false))?", entry)
        if not match:
            return None
        if match[2] != "false":
            enabled.add(match[1])
    return frozenset(enabled)


@dataclass(frozen=True)
class Restrictions:
    base: frozenset[str] | None
    effective: frozenset[str] | None


def parse_restrictions(output: str) -> Restrictions:
    matches = list(USER_HEADER.finditer(output))
    if len(matches) != 1:
        raise RepairError("Could not identify one user-0 block in dumpsys user.")
    header = matches[0]
    # UserInfo flags: GUEST=0x4, RESTRICTED=0x8, MANAGED_PROFILE=0x20.
    # INITIALIZED=0x10 is deliberately allowed (normal owner flags are often 0x13).
    if int(header[2], 16) & (0x4 | 0x8 | 0x20):
        raise RepairError("Refusing to change a guest, restricted user, or managed profile.")
    indent = len(header[1])
    lines = []
    for line in output[header.end():].splitlines():
        if line.strip() and len(line) - len(line.lstrip()) <= indent:
            break
        lines.append(line)
    block = "\n".join(lines)
    return Restrictions(restriction_section(block, "Restrictions:"),
                        restriction_section(block, "Effective restrictions:"))


def read_restrictions(adb: Adb) -> Restrictions:
    adb.require_owner_user()
    return parse_restrictions(adb.run("shell", "dumpsys", "user"))


def wallpaper_service_present(output: str) -> bool:
    if output.strip() == "Service wallpaper: found":
        return True
    if output.strip() == "Service wallpaper: not found":
        return False
    raise RepairError("Wallpaper service status is unknown; no repair will be attempted.")


def show_restrictions(state: Restrictions, emit: Callable[[str], None]) -> None:
    for key in WALLPAPER_KEYS:
        base = "unknown" if state.base is None else str(key in state.base).lower()
        effective = "unknown" if state.effective is None else str(key in state.effective).lower()
        emit(f"{key}: base={base}, effective={effective}")


def repair(adb: Adb, *, apply: bool = False, open_picker: bool = False,
           emit: Callable[[str], None] = print) -> int:
    """Return 0 for verified-clear restrictions, 2 for unresolved/unsupported state."""
    before = read_restrictions(adb)
    show_restrictions(before, emit)
    if not wallpaper_service_present(adb.run("shell", "service", "check", "wallpaper")):
        emit("This firmware exposes no wallpaper service. Restriction commands cannot add it.")
        return 2
    if before.base is None or before.effective is None:
        emit("Restriction state is unverified (missing, null, or unfamiliar dump). No changes.")
        return 2
    active = set(WALLPAPER_KEYS) & before.effective
    eligible = set(WALLPAPER_KEYS) & before.base
    if not eligible.issubset(active):
        emit("Base/effective restrictions disagree. No changes; collect fresh diagnostics.")
        return 2
    if active and not apply:
        emit("Read-only check. --apply can clear detected base wallpaper restrictions only.")
        return 2
    if active - eligible:
        emit("A wallpaper restriction has no matching base restriction; it may be enforced "
             "by device policy. No changes; this tool does not remove administrators.")
        return 2
    if eligible:
        help_text = adb.run("shell", "pm", "help")
        if not re.search(r"set-user-restriction\s+\[--user\s+[^\]]+\]", help_text):
            emit("Firmware does not advertise the required pm set-user-restriction syntax.")
            return 2
        errors = []
        for key in WALLPAPER_KEYS:
            if key not in eligible:
                continue
            try:
                adb.require_owner_user()
                output = adb.run("shell", "pm", "set-user-restriction", "--user", "0", key, "0")
                if output:
                    raise RepairError(f"Unexpected response while clearing {key}: {output}")
            except RepairError as error:
                errors.append(str(error))
                break
        after = read_restrictions(adb)
        emit("After attempted repair:")
        show_restrictions(after, emit)
        if after.base is not None:
            for key in WALLPAPER_KEYS:
                if key in eligible and key not in after.base:
                    emit(f"Cleared base {key}. To restore this original flag only: "
                         f"adb -s YOUR_SERIAL shell pm set-user-restriction --user 0 {key} 1")
        for error in errors:
            emit(error)
        if (errors or after.effective is None or after.base is None
                or set(WALLPAPER_KEYS) & (after.effective | after.base)):
            emit("Repair is not verified. A device policy may still enforce the restriction; "
                 "do not treat a successful shell exit as proof of a fix.")
            return 2
    emit("No wallpaper restrictions detected for user 0. This does not prove that the "
         "firmware or launcher can actually apply a wallpaper; test on the tablet.")
    if open_picker:
        adb.require_owner_user()
        adb.run("shell", "am", "start", "--user", "0", "-a", "android.intent.action.SET_WALLPAPER")
        emit("Wallpaper picker requested. Confirm that it opens and applies your image.")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--adb", default="adb", help="ADB executable path (including adb.exe on Windows)")
    parser.add_argument("--serial", help="Explicit adb device serial or Wi-Fi address:port")
    parser.add_argument("--apply", action="store_true", help="Clear detected base wallpaper restrictions")
    parser.add_argument("--open-picker", action="store_true", help="Open picker only after verified-clear restrictions")
    args = parser.parse_args(argv)
    adb = Adb(args.adb, args.serial)
    try:
        adb.select_device()
        return repair(adb, apply=args.apply, open_picker=args.open_picker)
    except RepairError as error:
        print(f"Stopped: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
