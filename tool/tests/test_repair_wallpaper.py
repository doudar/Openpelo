"""Offline tests: fixtures model AOSP dump formatting, not captured Peloton output."""

import contextlib
import io
from pathlib import Path
import subprocess
import sys
import unittest
from unittest.mock import Mock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import repair_wallpaper as rw


def dump(base="no_set_wallpaper", effective="no_set_wallpaper", flags="13"):
    return f"""Users:
  UserInfo{{0:Owner:{flags}}} serialNo=0
    State: RUNNING_UNLOCKED
    Restrictions:
      {base}
    Device policy local restrictions:
      none
    Effective restrictions:
      {effective}
  UserInfo{{10:Work:30}} serialNo=10
    Restrictions:
      no_wallpaper
    Effective restrictions:
      no_wallpaper
  Device policy global restrictions:
    no_set_wallpaper
"""


class FakeAdb(rw.Adb):
    def __init__(self, dumps, *, service="Service wallpaper: found",
                 help_text="set-user-restriction [--user USER_ID] RESTRICTION VALUE",
                 current_users=None, responses=None):
        self.dumps = list(dumps)
        self.service = service
        self.help_text = help_text
        self.current_users = list(current_users or [])
        self.responses = responses or {}
        self.commands = []

    def run(self, *args, **kwargs):
        self.commands.append(args)
        if args == ("shell", "am", "get-current-user"):
            return self.current_users.pop(0) if self.current_users else "0"
        if args == ("shell", "dumpsys", "user"):
            return self.dumps.pop(0)
        if args == ("shell", "service", "check", "wallpaper"):
            return self.service
        if args == ("shell", "pm", "help"):
            return self.help_text
        if args in self.responses:
            result = self.responses[args]
            if isinstance(result, Exception):
                raise result
            return result
        if args[:3] == ("shell", "pm", "set-user-restriction"):
            return ""
        if args[:3] == ("shell", "am", "start"):
            return "Starting: Intent { act=android.intent.action.SET_WALLPAPER }"
        raise AssertionError(f"Unexpected command: {args}")

    @property
    def writes(self):
        return [c for c in self.commands if c[:3] == ("shell", "pm", "set-user-restriction")]

    @property
    def picker_opened(self):
        return any(c[:3] == ("shell", "am", "start") for c in self.commands)


CLEAR_SET = ("shell", "pm", "set-user-restriction", "--user", "0", "no_set_wallpaper", "0")
CLEAR_WALLPAPER = ("shell", "pm", "set-user-restriction", "--user", "0", "no_wallpaper", "0")


class ParserTests(unittest.TestCase):
    def test_target_user_does_not_include_other_users_or_global_sections(self):
        state = rw.parse_restrictions(dump("none", "none"))
        self.assertEqual(state.base, frozenset())
        self.assertEqual(state.effective, frozenset())

    def test_bare_keys_and_boolean_variants(self):
        state = rw.parse_restrictions(dump("no_wallpaper\n      no_camera",
                                          "no_wallpaper=true\n      no_set_wallpaper=false"))
        self.assertEqual(state.base, {"no_wallpaper", "no_camera"})
        self.assertEqual(state.effective, {"no_wallpaper"})

    def test_null_and_missing_are_unknown(self):
        self.assertIsNone(rw.parse_restrictions(dump("null", "null")).effective)
        state = rw.parse_restrictions(dump().replace("Effective restrictions:", "Unknown heading:"))
        self.assertIsNone(state.effective)

    def test_unrecognized_or_duplicate_section_is_unknown(self):
        self.assertIsNone(rw.parse_restrictions(dump("Bundle[{no_wallpaper=true}]")).base)
        text = dump().replace("    State: RUNNING_UNLOCKED", "    Restrictions:\n      none")
        self.assertIsNone(rw.parse_restrictions(text).base)

    def test_normal_initialized_owner_allowed(self):
        self.assertEqual(rw.parse_restrictions(dump(flags="13")).base, {"no_set_wallpaper"})

    def test_guest_restricted_and_managed_profiles_rejected(self):
        for flags in ("17", "1b", "33"):
            with self.subTest(flags=flags), self.assertRaises(rw.RepairError):
                rw.parse_restrictions(dump(flags=flags))

    def test_missing_and_duplicate_owner_rejected(self):
        for text in ("Permission Denial", dump() + dump(), dump().replace("{0:", "{1:")):
            with self.subTest(text=text[:30]), self.assertRaises(rw.RepairError):
                rw.parse_restrictions(text)

    def test_crlf_and_colon_in_username(self):
        text = dump().replace("Owner:", "Owner:Name:").replace("\n", "\r\n")
        self.assertEqual(rw.parse_restrictions(text).effective, {"no_set_wallpaper"})

    def test_empty_mixed_or_unrecognized_entries_are_unknown(self):
        for value in ("", "none\n      no_wallpaper", "unknown format!", "null\n      no_wallpaper"):
            with self.subTest(value=value):
                self.assertIsNone(rw.parse_restrictions(dump(value)).base)


class AdbTests(unittest.TestCase):
    def adb(self, stdout="", stderr="", code=0, serial="bike"):
        runner = Mock(return_value=subprocess.CompletedProcess([], code, stdout, stderr))
        return rw.Adb("/path with spaces/adb", serial, runner), runner

    def test_targets_serial_without_host_shell_and_has_timeout(self):
        adb, runner = self.adb("0")
        adb.require_owner_user()
        self.assertEqual(runner.call_args.args[0],
                         ["/path with spaces/adb", "-s", "bike", "shell", "am", "get-current-user"])
        self.assertEqual(runner.call_args.kwargs["timeout"], 20)
        self.assertNotIn("shell", runner.call_args.kwargs)

    def test_exit_zero_android_errors_are_rejected(self):
        for text in ("java.lang.SecurityException: denied", "Error type 3", "Unknown command: x",
                     "Permission Denial: blocked", "Failure [NOT_ALLOWED]"):
            with self.subTest(text=text), self.assertRaises(rw.RepairError):
                self.adb(text)[0].run("shell", "pm")

    def test_stderr_errors_and_nonzero_exit_are_rejected(self):
        for kwargs in ({"stderr": "Permission denied"}, {"code": 1}):
            with self.subTest(kwargs=kwargs), self.assertRaises(rw.RepairError):
                self.adb(**kwargs)[0].run("shell", "pm")

    def test_timeout_and_missing_binary_are_wrapped(self):
        for error in (FileNotFoundError("adb"), subprocess.TimeoutExpired("adb", 20)):
            adb, runner = self.adb()
            runner.side_effect = error
            with self.assertRaises(rw.RepairError):
                adb.run("devices", targeted=False)

    def test_selects_one_authorized_device(self):
        adb, _ = self.adb("List of devices attached\nbike\tdevice\n", serial=None)
        adb.select_device()
        self.assertEqual(adb.serial, "bike")

    def test_ambiguous_absent_or_unauthorized_devices_refused(self):
        for entries in ("", "bike\tunauthorized", "bike\toffline", "bike\tdevice\nother\tdevice",
                        "bike\tdevice\nother\trecovery", "bike\tdevice\nother\tno permissions"):
            adb, _ = self.adb("List of devices attached\n" + entries, serial=None)
            with self.subTest(entries=entries), self.assertRaises(rw.RepairError):
                adb.select_device()

    def test_explicit_device_selection(self):
        adb, _ = self.adb("List of devices attached\nbike\tdevice\nother\tdevice")
        adb.select_device()
        for entries in ("other\tdevice", "bike\tunauthorized"):
            with self.subTest(entries=entries), self.assertRaises(rw.RepairError):
                self.adb("List of devices attached\n" + entries)[0].select_device()

    def test_requires_selection_before_targeted_command(self):
        with self.assertRaises(rw.RepairError):
            self.adb(serial=None)[0].run("shell", "pm")

    def test_nonzero_unknown_and_injected_current_user_rejected(self):
        for value in ("10", "", "current user: 0", "0; reboot", "-1"):
            with self.subTest(value=value), self.assertRaises(rw.RepairError):
                self.adb(value)[0].require_owner_user()


class RepairTests(unittest.TestCase):
    def run_repair(self, adb, **kwargs):
        messages = []
        result = rw.repair(adb, emit=messages.append, **kwargs)
        return result, "\n".join(messages)

    def test_read_only_is_default(self):
        adb = FakeAdb([dump()])
        result, _ = self.run_repair(adb)
        self.assertEqual(result, 2)
        self.assertEqual(adb.writes, [])
        self.assertFalse(adb.picker_opened)

    def test_clears_only_detected_base_key_and_preserves_other_restrictions(self):
        adb = FakeAdb([dump("no_set_wallpaper\n      no_camera", "no_set_wallpaper\n      no_camera"),
                       dump("no_camera", "no_camera")])
        result, messages = self.run_repair(adb, apply=True)
        self.assertEqual(result, 0)
        self.assertEqual(adb.writes, [CLEAR_SET])
        self.assertIn("no_set_wallpaper 1", messages)
        self.assertNotIn("no_wallpaper 1", messages)

    def test_clears_both_keys_in_order_and_then_opens_picker(self):
        keys = "no_set_wallpaper\n      no_wallpaper"
        adb = FakeAdb([dump(keys, keys), dump("none", "none")])
        result, _ = self.run_repair(adb, apply=True, open_picker=True)
        self.assertEqual(result, 0)
        self.assertEqual(adb.writes, [CLEAR_SET, CLEAR_WALLPAPER])
        self.assertTrue(adb.picker_opened)
        self.assertEqual(adb.commands[-1], ("shell", "am", "start", "--user", "0", "-a",
                                           "android.intent.action.SET_WALLPAPER"))

    def test_policy_only_restriction_is_not_modified(self):
        adb = FakeAdb([dump("none", "no_set_wallpaper")])
        result, messages = self.run_repair(adb, apply=True, open_picker=True)
        self.assertEqual(result, 2)
        self.assertIn("device policy", messages)
        self.assertEqual(adb.writes, [])
        self.assertFalse(adb.picker_opened)

    def test_effective_restriction_persisting_after_success_is_not_a_fix(self):
        adb = FakeAdb([dump(), dump("none", "no_set_wallpaper")])
        result, messages = self.run_repair(adb, apply=True, open_picker=True)
        self.assertEqual(result, 2)
        self.assertIn("Repair is not verified", messages)
        self.assertFalse(adb.picker_opened)

    def test_unknown_before_or_after_cannot_claim_success(self):
        for dumps in ([dump("null", "null")], [dump(), dump("none", "null")]):
            adb = FakeAdb(dumps)
            result, _ = self.run_repair(adb, apply=True, open_picker=True)
            self.assertEqual(result, 2)
            self.assertFalse(adb.picker_opened)

    def test_missing_service_prevents_changes(self):
        adb = FakeAdb([dump()], service="Service wallpaper: not found")
        result, _ = self.run_repair(adb, apply=True)
        self.assertEqual(result, 2)
        self.assertEqual(adb.writes, [])

    def test_unknown_service_prevents_changes(self):
        adb = FakeAdb([dump()], service="unrecognized vendor output")
        with self.assertRaises(rw.RepairError):
            self.run_repair(adb, apply=True)
        self.assertEqual(adb.writes, [])

    def test_unsupported_pm_syntax_prevents_changes(self):
        for help_text in ("other commands", "set-user-restriction RESTRICTION VALUE"):
            adb = FakeAdb([dump()], help_text=help_text)
            result, _ = self.run_repair(adb, apply=True)
            self.assertEqual(result, 2)
            self.assertEqual(adb.writes, [])

    def test_contradictory_base_and_effective_dump_stops(self):
        adb = FakeAdb([dump("no_wallpaper", "none")])
        self.assertEqual(self.run_repair(adb, apply=True)[0], 2)
        self.assertEqual(adb.writes, [])

    def test_clear_device_requires_no_pm_write(self):
        adb = FakeAdb([dump("none", "none")])
        result, messages = self.run_repair(adb, apply=True)
        self.assertEqual(result, 0)
        self.assertEqual(adb.writes, [])
        self.assertNotIn(("shell", "pm", "help"), adb.commands)
        self.assertIn("does not prove", messages)

    def test_command_error_is_reported_even_if_after_dump_is_clear(self):
        adb = FakeAdb([dump(), dump("none", "none")],
                      responses={CLEAR_SET: rw.RepairError("permission denied")})
        result, messages = self.run_repair(adb, apply=True, open_picker=True)
        self.assertEqual(result, 2)
        self.assertIn("permission denied", messages)
        self.assertFalse(adb.picker_opened)

    def test_unexpected_command_output_is_not_success(self):
        adb = FakeAdb([dump(), dump("none", "none")], responses={CLEAR_SET: "Usage: pm ..."})
        self.assertEqual(self.run_repair(adb, apply=True)[0], 2)

    def test_partial_failure_exposes_actual_changed_flags(self):
        keys = "no_set_wallpaper\n      no_wallpaper"
        adb = FakeAdb([dump(keys, keys), dump("no_wallpaper", "no_wallpaper")],
                      responses={CLEAR_WALLPAPER: rw.RepairError("second command failed")})
        result, messages = self.run_repair(adb, apply=True, open_picker=True)
        self.assertEqual(result, 2)
        self.assertIn("Cleared base no_set_wallpaper", messages)
        self.assertNotIn("Cleared base no_wallpaper", messages)
        self.assertFalse(adb.picker_opened)

    def test_user_switch_before_write_stops(self):
        adb = FakeAdb([dump(), dump()], current_users=["0", "10", "0"])
        result, _ = self.run_repair(adb, apply=True)
        self.assertEqual(result, 2)
        self.assertEqual(adb.writes, [])

    def test_picker_failure_is_not_swallowed(self):
        picker = ("shell", "am", "start", "--user", "0", "-a", "android.intent.action.SET_WALLPAPER")
        adb = FakeAdb([dump("none", "none")], responses={picker: rw.RepairError("unable to resolve Intent")})
        with self.assertRaises(rw.RepairError):
            self.run_repair(adb, open_picker=True)

    def test_cli_failure_is_concise_and_nonzero(self):
        with patch.object(rw.Adb, "select_device", side_effect=rw.RepairError("not authorized")):
            with contextlib.redirect_stderr(io.StringIO()) as output:
                self.assertEqual(rw.main([]), 2)
            self.assertIn("Stopped: not authorized", output.getvalue())


if __name__ == "__main__":
    unittest.main()
