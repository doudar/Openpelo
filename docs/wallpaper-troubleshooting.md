# Wallpaper is “Disabled by your admin”

Related report: [OpenPelo #70](https://github.com/doudar/Openpelo/issues/70).

Android has two relevant user restrictions: `no_set_wallpaper` blocks changing
wallpaper, while `no_wallpaper` blocks access to wallpaper APIs. A base user
restriction may be clearable over ADB. A device/profile-owner policy is separate:
clearing a base restriction does **not** override that policy. Firmware may also
omit the wallpaper service, which these commands cannot restore.

This is an **experimental, opt-in troubleshooting tool**, not a confirmed fix
for every Peloton. It is a standalone Python helper in the source checkout, not
a new button in the packaged OpenPelo application. It does not run during app
installation or launcher setup. No affected Peloton has been hardware-tested
with this change yet.

## Guarded helper (recommended)

Use Python 3.10 or newer and an authorized ADB connection to your own tablet.
`adb` must be on PATH, or supply `--adb` with the full path to an existing
platform-tools `adb`/`adb.exe`. OpenPelo's selected target is **not** automatically
shared with this standalone helper. Run `adb devices` and use the intended
serial (or Wi-Fi `address:port`). Run these commands from the repository root:

```sh
# Read-only: inspect base/effective restrictions and wallpaper-service presence.
python3 tool/repair_wallpaper.py --serial YOUR_SERIAL

# Explicitly allow the targeted repair, then request the Android wallpaper picker.
python3 tool/repair_wallpaper.py --serial YOUR_SERIAL --apply --open-picker
```

On Windows, use `py -3` instead of `python3`, for example:

```powershell
py -3 tool/repair_wallpaper.py --adb "C:\platform-tools\adb.exe" --serial YOUR_SERIAL --apply --open-picker
```

The helper requires **active Android user 0** and refuses guest/restricted/managed
profiles, ambiguous device selection, unfamiliar policy dumps, missing wallpaper
service, unsupported commands, and permission failures. It clears only wallpaper
flags actually found in the user's **base** restrictions. It reads the effective
restrictions again afterward and will not open the picker if verification fails.
Other restrictions, administrators, packages, provisioning settings, and app data
are left unchanged. Android errors printed with exit status zero are treated as
failures. Partial changes are reported when the post-check is available.

Exit status `0` means the parsed wallpaper restrictions are clear, **not** that
a wallpaper was successfully applied. Status `2` means unresolved restrictions,
an unsupported/unknown state, or a command failure. Without `--apply`, a reported
restriction also returns `2`; that read-only check has changed nothing.
`--open-picker` is separately opt-in because it opens an activity on the tablet.

Choose an image in the picker and verify the Lawnchair background. Then check
again after reopening the Peloton app and after a reboot: firmware may reapply
its restrictions. An “unable to resolve Intent” error means there is no matching
picker activity; removing restrictions cannot install a missing picker.

## Underlying ADB commands

First inspect, without changing anything (replace `YOUR_SERIAL`):

```sh
adb -s YOUR_SERIAL shell am get-current-user
adb -s YOUR_SERIAL shell service check wallpaper
adb -s YOUR_SERIAL shell dumpsys user
adb -s YOUR_SERIAL shell dumpsys device_policy
adb -s YOUR_SERIAL shell pm help
```

Do not assume user 0 is active. In that user's dump, distinguish `Restrictions:`
(base) from `Effective restrictions:` and device-policy restrictions. A `null`,
missing, or unfamiliar effective section is **not** proof that restrictions are
absent. The helper intentionally stops in that case.

Only with active user 0, a present wallpaper service, supported command syntax,
and the corresponding flag set in **base** restrictions, the candidate commands
are:

```sh
adb -s YOUR_SERIAL shell pm set-user-restriction --user 0 no_set_wallpaper 0
adb -s YOUR_SERIAL shell pm set-user-restriction --user 0 no_wallpaper 0
adb -s YOUR_SERIAL shell dumpsys user
```

Run only the clear command for each flag that was originally set. Check effective
restrictions afterward; a silent command with exit status zero alone is not
verification. If both are clear, request the existing wallpaper picker:

```sh
adb -s YOUR_SERIAL shell am start --user 0 -a android.intent.action.SET_WALLPAPER
```

To undo a cleared base flag, use the same `pm set-user-restriction` command with
`1` instead of `0`, **only for a flag known to have been set before this repair**.
The helper prints those restoration commands for verified base changes. Do not
set both flags blindly; that could introduce a restriction that was never there.

## When this does not work

A wallpaper restriction that is effective but absent from base restrictions may
be enforced by device policy. A base flag can also be cleared successfully while
a separate owner policy keeps the effective restriction enabled. These are not
successful repairs. Do not remove a device owner, disable Peloton system apps,
change provisioning flags, or factory-reset the tablet just to change wallpaper.
Likewise, `settings put ... no_set_wallpaper 0` does not operate on UserManager's
restriction storage, and granting an app wallpaper permission does not clear a
user restriction.

For follow-up on #70, include the Android version, whether `service check
wallpaper` reports `found`, the helper's two restriction-status lines, and any
error text. Only share relevant restriction sections from diagnostic dumps;
`dumpsys user` and `dumpsys device_policy` can include account/device information.

## Implementation references and validation

- [Android UserManager: DISALLOW_SET_WALLPAPER](https://developer.android.com/reference/android/os/UserManager#DISALLOW_SET_WALLPAPER)
- [AOSP UserManager: both wallpaper restriction keys](https://android.googlesource.com/platform/prebuilts/fullsdk/sources/android-30/+/refs/heads/main/android/os/UserManager.java)
- [AOSP PackageManager shell: runSetUserRestriction](https://android.googlesource.com/platform/frameworks/base/+/525db8eac45707d98bb170905df754913651ec1a/services/core/java/com/android/server/pm/PackageManagerShellCommand.java)
- [AOSP UserManagerService: separate base and effective policy restrictions](https://android.googlesource.com/platform/frameworks/base/+/ef2342c/services/core/java/com/android/server/pm/UserManagerService.java)
- [AOSP restriction-dump formatting](https://android.googlesource.com/platform/frameworks/base/+/master/services/core/java/com/android/server/pm/UserRestrictionsUtils.java)

Run the offline tests with:

```sh
python3 -m unittest discover -s tool/tests -p 'test_repair_wallpaper.py' -v
```

Fixtures model AOSP formatting; they are not captured Peloton results. Tests cover
read-only operation, device/user targeting, base versus policy restrictions,
unknown/null dumps, missing service, unsupported commands, permission errors,
partial failures, post-change verification, and conditional picker launch.
The existing build workflow's `tool/tests/test_*.py` discovery includes these tests.
