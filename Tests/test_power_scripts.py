"""Run sandbox copies of the real scripts. No root tool or system path is used."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

PROJECT = Path(__file__).resolve().parent.parent
INITIAL = {"disabled": 0, "ac": {"sleep": 8, "displaysleep": 12, "disksleep": 14, "womp": 0,
           "tcpkeepalive": 0, "powernap": 0, "ttyskeepawake": 0, "hibernatemode": 3},
           "battery": {"sleep": 3, "displaysleep": 4, "disksleep": 6, "womp": 0,
           "tcpkeepalive": 0, "powernap": 0, "ttyskeepawake": 0, "hibernatemode": 3}}
FAKE = r'''
import json, os, pathlib, subprocess, sys
root = pathlib.Path(os.environ["POWER_TEST_ROOT"])
name, args = pathlib.Path(sys.argv[0]).name, sys.argv[1:]
if name == "fake-id": print(os.environ.get("POWER_TEST_UID", "0"))
elif name == "fake-stat": print(os.environ.get("POWER_TEST_CONSOLE_UID", "501"))
elif name == "fake-sudo":
    assert args[:3] == ["-H", "-u", "#501"], args
    sys.exit(subprocess.call(args[3:], env=dict(os.environ, POWER_TEST_EFFECTIVE_UID="501")))
elif name == "fake-defaults":
    assert os.environ.get("POWER_TEST_EFFECTIVE_UID", os.environ.get("POWER_TEST_UID")) == "501", "must not write root preferences"
    path = root / "screensaver.json"
    prefs = json.loads(path.read_text())
    host = args[0] == "-currentHost"
    if host: args = args[1:]
    action, domain, key = args[:3]
    assert domain == "com.apple.screensaver" and key == "idleTime", args
    scope = "host" if host else "any"
    if action == "read":
        if scope not in prefs: sys.exit(1)
        print(prefs[scope])
    elif action == "write":
        assert args[3] == "-int", args
        prefs[scope] = int(args[4])
        path.write_text(json.dumps(prefs))
        with (root / "writes.log").open("a") as log: log.write(args[4] + "\n")
    else: raise AssertionError(action)
elif name == "fake-chown": pass
elif name == "fake-install":
    cleaned, i = [], 0
    while i < len(args):
        if args[i] in ("-o", "-g"): i += 2
        else: cleaned.append(args[i]); i += 1
    sys.exit(subprocess.call(["/usr/bin/install"] + cleaned))
elif name == "fake-launchctl":
    loaded = root / "loaded"
    if args[0] == "asuser":
        assert args[1] == "501", args
        sys.exit(subprocess.call(args[2:]))
    elif args[0] == "bootout": loaded.unlink(missing_ok=True)
    elif args[0] == "bootstrap":
        if os.environ.get("POWER_TEST_FAIL") == "1": sys.exit(5)
        loaded.touch()
elif name == "fake-pmset":
    path = root / "pmset.json"
    state = json.loads(path.read_text())
    if args == ["-g", "custom"]:
        for section, title in [("battery", "Battery Power:"), ("ac", "AC Power:")]:
            print(title)
            for key, value in state[section].items(): print(" " + key + " " + str(value))
    elif args == ["-g"]: print("System-wide power settings:\n SleepDisabled " + str(state["disabled"]))
    else:
        assert args[0] in ("-a", "-c", "-b"), args
        for key, value in zip(args[1::2], args[2::2]):
            if key == "disablesleep": state["disabled"] = int(value)
            else:
                targets = ("ac", "battery") if args[0] == "-a" else (("ac",) if args[0] == "-c" else ("battery",))
                for target in targets: state[target][key] = int(value)
        path.write_text(json.dumps(state))
else: raise AssertionError(name)
'''


def main():
    with tempfile.TemporaryDirectory(prefix="power-scripts-test-") as directory:
        root = Path(directory)
        sources, daemon, state = root / "sources", root / "LaunchDaemons", root / "State"
        sources.mkdir()
        daemon.mkdir()
        replacements = {"/Library/LaunchDaemons": str(daemon), "/usr/local/sbin": str(root / "sbin"),
                        "/Library/Application Support/com.yuwangzhi.power-management": str(state)}
        tools = {"id": "/usr/bin/id", "install": "/usr/bin/install", "pmset": "/usr/bin/pmset",
                 "chown": "/usr/sbin/chown", "launchctl": "/bin/launchctl", "stat": "/usr/bin/stat",
                 "sudo": "/usr/bin/sudo", "defaults": "/usr/bin/defaults"}
        for tool, original in tools.items():
            replacement = root / ("fake-" + tool)
            replacement.write_text("#!/usr/bin/python3\n" + FAKE)
            replacement.chmod(0o755)
            replacements[original] = str(replacement)
        for filename in ["install.sh", "restore-default-sleep.sh", "power-settings.sh", "codex-power-keepawake.sh",
                         "screensaver-settings.sh", "com.yuwangzhi.codex-power-keepawake.plist"]:
            content = (PROJECT / filename).read_text()
            for original, replacement in replacements.items(): content = content.replace(original, replacement)
            (sources / filename).write_text(content)
        settings_file = root / "pmset.json"
        settings_file.write_text(json.dumps(INITIAL))
        screensaver_file = root / "screensaver.json"
        screensaver_file.write_text(json.dumps({"host": 600, "any": 300}))

        def run(script, failure=False, args=(), **extra_env):
            env = dict(os.environ, POWER_TEST_ROOT=str(root), POWER_TEST_FAIL="1" if failure else "0",
                       POWER_TEST_UID="0")
            env.update(extra_env)
            result = subprocess.run(["/bin/zsh", str(sources / script), *args], env=env, capture_output=True, text=True)
            assert (result.returncode != 0) == failure, result.stdout + result.stderr
            return result

        run("install.sh")
        enabled = json.loads(settings_file.read_text())
        assert enabled["disabled"] == 1 and (root / "loaded").exists()
        assert json.loads(screensaver_file.read_text()) == {"host": 0, "any": 300}
        for section in ["ac", "battery"]:
            assert all(enabled[section][key] == 0 for key in ["sleep", "displaysleep", "disksleep"])
        original_backup = (state / "custom.txt").read_text()
        writes = (root / "writes.log").read_text()
        run("install.sh")
        assert (state / "custom.txt").read_text() == original_backup
        assert (root / "writes.log").read_text() == writes, "unchanged screen saver must not be rewritten"
        screensaver_file.write_text(json.dumps({"host": 1200, "any": 300}))
        run("codex-power-keepawake.sh")
        assert json.loads(screensaver_file.read_text())["host"] == 0, "background service must correct drift"
        run("restore-default-sleep.sh")
        assert json.loads(settings_file.read_text()) == INITIAL
        assert json.loads(screensaver_file.read_text()) == {"host": 1200, "any": 300}
        assert not (root / "loaded").exists() and not state.exists()
        assert not (daemon / "com.yuwangzhi.codex-power-keepawake.plist").exists()
        assert not (root / "sbin" / "screensaver-settings.sh").exists()
        screensaver_file.write_text(json.dumps({"host": 600, "any": 300}))
        run("install.sh", failure=True)
        assert json.loads(settings_file.read_text()) == INITIAL
        assert json.loads(screensaver_file.read_text()) == {"host": 600, "any": 300}, "failed enable must restore original screen saver"
        assert not state.exists() and not (root / "loaded").exists()
        result = run("restore-default-sleep.sh")
        restored = json.loads(settings_file.read_text())
        assert restored["disabled"] == 0 and restored["ac"]["displaysleep"] == 10
        assert restored["battery"]["displaysleep"] == 5
        assert "Restored legacy normal sleep defaults." in result.stdout
        assert json.loads(screensaver_file.read_text())["host"] == 1200
        screensaver_file.write_text(json.dumps({"any": 300}))
        assert run("screensaver-settings.sh", args=("read",)).stdout.strip() == "300"
        screensaver_file.write_text("{}")
        assert run("screensaver-settings.sh", args=("read",)).stdout.strip() == "1200"
        run("screensaver-settings.sh", args=("0",), POWER_TEST_CONSOLE_UID="0")
        assert json.loads(screensaver_file.read_text()) == {}, "login window must not change root preferences"
        assert run("screensaver-settings.sh", args=("read",), POWER_TEST_CONSOLE_UID="0").stdout.strip() == "unavailable"
        for invalid in ["-1", "oops", "86401", "$(touch should-not-exist)"]:
            run("screensaver-settings.sh", failure=True, args=(invalid,))
        run("screensaver-settings.sh", args=("0",), POWER_TEST_UID="501")
        assert json.loads(screensaver_file.read_text()) == {"host": 0}
    print("Power scripts: enable/disable, 0/1200-second screen saver, user context, drift repair, rollback, defaults and legacy restore passed in isolation.")


if __name__ == "__main__":
    main()
