"""Resolve an agent to a local Hyprland window without guessing between windows."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

PROC = Path("/proc")
ADDRESS = re.compile(r"0x[0-9a-fA-F]+")
IDE_CLASSES = re.compile(r"code(?:-oss|-insiders)?|vscodium(?:-insiders)?|cursor|windsurf|zed(?:-preview)?|jetbrains-.+")


def hypr_json(command):
    try:
        return json.loads(subprocess.check_output(
            ["hyprctl", "-j", command], stderr=subprocess.DEVNULL, timeout=1))
    except (OSError, ValueError, subprocess.SubprocessError):
        return []


def process_start(pid):
    try:
        return (PROC / str(pid) / "stat").read_text().rsplit(")", 1)[1].split()[19]
    except (OSError, IndexError, UnicodeError):
        return None


def parents(pid):
    while pid > 1:
        yield pid
        try:
            pid = int((PROC / str(pid) / "stat").read_text().rsplit(")", 1)[1].split()[1])
        except (OSError, ValueError, IndexError, UnicodeError):
            return


def clients():
    return [
        w for w in hypr_json("clients")
        if w.get("mapped") and ADDRESS.fullmatch(w.get("address", ""))
    ]


def owned(windows, pid):
    for ancestor in parents(pid):
        candidates = [w for w in windows if w.get("pid") == ancestor]
        if candidates:
            return candidates
    return []


def window_hint(pid):
    matches = owned(clients(), pid)
    if len(matches) == 1:
        window = matches[0]
    elif matches:
        active = hypr_json("activewindow")
        window = next((w for w in matches if isinstance(active, dict) and w["address"] == active.get("address")), None)
    else:
        window = None
    return {"address": window["address"], "pid": window["pid"]} if window else None


def proc_args(proc):
    try:
        return (proc / "cmdline").read_bytes().rstrip(b"\0").decode(errors="replace").split("\0")
    except OSError:
        return []


def proc_cwd(proc):
    try:
        return os.readlink(proc / "cwd")
    except OSError:
        return ""


def holds_file(proc, path):
    try:
        for fd in (proc / "fd").iterdir():
            try:
                if os.readlink(fd) == path:
                    return True
            except OSError:
                continue
    except OSError:
        pass
    return False


def claude_pids(session_id):
    found = []
    roots = list(Path.home().glob(".claude*"))
    if os.environ.get("CLAUDE_CONFIG_DIR"):
        roots.append(Path(os.environ["CLAUDE_CONFIG_DIR"]))
    for root in set(roots):
        for marker in (root / "sessions").glob("[0-9]*.json"):
            try:
                data = json.loads(marker.read_bytes())
                if data.get("sessionId", data.get("session_id")) == session_id:
                    found.append(int(marker.stem))
            except (OSError, ValueError, AttributeError):
                continue
    return found


def unique(matches):
    selected = {w["address"]: w for w in matches}
    return next(iter(selected.values())) if len(selected) == 1 else None


def resolve(session, windows):
    hint = session.get("window") or {}
    for window in windows:
        if window["address"] == hint.get("address") and window.get("pid") == hint.get("pid"):
            return window

    owner = session.get("ownerPid")
    owner_start = session.get("ownerStart")
    if isinstance(owner, int) and owner_start and process_start(owner) == owner_start:
        target = unique(owned(windows, owner))
        if target:
            return target

    provider = session.get("provider")
    path = session.get("transcript")
    cwd = session.get("cwd")
    name = session.get("name", "")
    if provider == "external":
        if name == "OpenCode":
            matches = [w for w in windows if "opencode" in w.get("class", "").lower()]
            return matches[0] if len(matches) == 1 else None
        return None

    exact = []
    terminal = []
    if provider == "claude":
        for pid in claude_pids(str(session.get("id", "")).removeprefix("claude:")):
            exact.extend(owned(windows, pid))
    for proc in PROC.iterdir():
        if not proc.name.isdecimal():
            continue
        try:
            comm = (proc / "comm").read_text().strip().lower()
        except OSError:
            continue
        if comm not in (("codex",) if provider == "codex" else ("claude", "claude-code")):
            continue
        matches = owned(windows, int(proc.name))
        if not matches:
            continue
        args = proc_args(proc)
        if (path and holds_file(proc, path)) or (path and session["id"].split(":", 1)[-1] in args):
            exact.extend(matches)
        elif cwd and proc_cwd(proc) == cwd and "app-server" not in args:
            terminal.extend(matches)

    if exact:
        return unique(exact)
    if name == "Codex Desktop":
        return unique([w for w in windows if any(
            label in w.get("class", "").lower() for label in ("chatgpt", "codex"))])
    if name == "Codex IDE":
        if session.get("origin") == "codex-tui" and terminal:
            return unique(terminal)
        ide = [w for w in windows if IDE_CLASSES.fullmatch(w.get("class", "").lower())]
        if ide:
            return unique(ide)
    return unique(terminal)


def dispatch(expression):
    try:
        result = subprocess.run(["hyprctl", "dispatch", expression], capture_output=True, text=True, timeout=1)
        return result.returncode == 0 and result.stdout.strip() == "ok"
    except (OSError, subprocess.SubprocessError):
        return False


def focus_window(window):
    workspace = window.get("workspace", {}).get("name", "")
    if workspace.startswith("special:"):
        visible = any(
            monitor.get("specialWorkspace", {}).get("name") == workspace
            for monitor in hypr_json("monitors")
        )
        if not visible:
            name = json.dumps(workspace.removeprefix("special:"), ensure_ascii=False)
            if not dispatch(f"hl.dsp.workspace.toggle_special({name})"):
                return False
    address = window["address"]
    return bool(ADDRESS.fullmatch(address)) and dispatch(f'hl.dsp.focus({{ window = "address:{address}" }})')


if __name__ == "__main__":
    try:
        target = resolve(json.loads(sys.argv[1]), clients())
    except (IndexError, ValueError, OSError):
        target = None
    sys.exit(0 if target and focus_window(target) else 1)
