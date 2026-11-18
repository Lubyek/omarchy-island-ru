#!/usr/bin/env python3
"""Publish activity states from local Codex/Claude transcripts and IDE/CLI hooks."""
import calendar
from datetime import date, timedelta
import glob
import json
import os
from pathlib import Path
import time

POLL = 0.5          # seconds between looks at the sessions in play
RELIST = 3          # seconds between looks for new transcripts
IDLE = 10 * 60      # a session silent this long is no longer shown
ASKING_IDLE = 60 * 60  # ...unless it's waiting on your answer
DONE_KEPT = 6      # seconds a finished turn stays listed
TAIL = 1 << 20      # Claude transcripts frequently carry only the recent turn here
CODEX_TAIL = 16 << 20  # Tool results and UI events can fill several MiB in one Codex turn
CODEX_START = ("task_started", "turn_started")
CODEX_FINISH = ("task_complete", "turn_completed", "turn_aborted")
CODEX_TOOL_IN = ("function_call", "custom_tool_call")
CODEX_TOOL_OUT = ("function_call_output", "custom_tool_call_output")
CODEX_EVENTS = tuple(f'"{kind}"'.encode() for kind in CODEX_START + CODEX_FINISH)
MAX_SESSIONS = 24
ASKING_TOOLS = ("AskUserQuestion", "ExitPlanMode")  # the tools that wait on your answer


def now_ms():
    return int(time.time() * 1000)


def iso_ms(ts):
    try:
        return calendar.timegm(time.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S")) * 1000 + int(ts[20:23] or 0)
    except (TypeError, ValueError):
        return now_ms()


class Session:
    def __init__(self, path, provider):
        self.path = path
        self.provider = provider
        self.name = "Claude Code" if provider == "claude" else "Codex"
        self.meta_read = False
        self.hidden = False
        self.turn = None
        self.cwd = ""
        self.origin = ""
        self.id = os.path.splitext(os.path.basename(path))[0]
        self.offset = 0
        self.running = {}      # the turn's running steps by id: whether it's asking
        self.state = ""        # "", thinking, tool, asking, done
        self.started = 0
        self.done_at = 0
        self.asked_at = 0
        self.question_id = ""
        self.updated = 0

    def read(self):
        try:
            size = os.path.getsize(self.path)
        except OSError:
            return
        if size < self.offset:
            self.__init__(self.path, self.provider)
        if size == self.offset:
            return
        limit = CODEX_TAIL if self.provider == "codex" else TAIL
        start = max(self.offset, size - limit)
        skipped = start > self.offset
        try:
            with open(self.path, "rb") as f:
                if self.provider == "codex" and not self.meta_read:
                    self.read_codex_meta(f.readline(TAIL))
                if self.hidden:
                    return
                f.seek(start)
                data = f.read(size - start)
        except OSError:
            return
        # A line still being written waits for the next look.
        end = data.rfind(b"\n") + 1
        self.offset = start + end
        if skipped:
            newline = data.find(b"\n")
            if newline < 0:
                return
            data, end = data[newline + 1:], end - newline - 1
        for line in data[:end].splitlines():
            if self.provider == "codex":
                event = b'"event_msg"' in line and any(kind in line for kind in CODEX_EVENTS)
                tool = b'"response_item"' in line and (b'"function_call' in line or b'"custom_tool_call' in line)
                if not event and not tool:
                    continue
            try:
                self.take(json.loads(line))
            except (ValueError, AttributeError, TypeError):
                pass

    def read_codex_meta(self, line):
        try:
            entry = json.loads(line)
            if entry.get("type") != "session_meta":
                return
            meta = entry.get("payload") or {}
            source = meta.get("source")
            self.origin = str(meta.get("originator", "")).lower()
            self.id = meta.get("id") or self.id
            self.cwd = meta.get("cwd") or ""
            if isinstance(source, dict) and "subagent" in source:
                self.hidden = True
            elif "desktop" in self.origin or "chatgpt" in self.origin:
                self.name = "Codex Desktop"
            elif source == "vscode":
                self.name = "Codex IDE"
            elif source in ("cli", "exec"):
                self.name = "Codex CLI"
        except (ValueError, AttributeError, TypeError):
            return
        self.meta_read = True

    def take_codex(self, entry):
        payload = entry.get("payload") or {}
        kind = payload.get("type")
        if entry.get("type") == "response_item":
            call = payload.get("call_id")
            if call and self.state not in ("", "done"):
                if kind in CODEX_TOOL_IN:
                    asking = str(payload.get("name", "")).endswith(("request_user_input", "request_user_input_async"))
                    self.start_tool(call, asking, iso_ms(entry.get("timestamp")))
                elif kind in CODEX_TOOL_OUT:
                    self.running.pop(call, None)
                else:
                    return
                self.state = self.working()
            return
        if entry.get("type") != "event_msg":
            return
        if kind not in CODEX_START + CODEX_FINISH:
            return
        stamp = iso_ms(entry.get("timestamp"))
        self.updated = max(self.updated, stamp)
        turn = payload.get("turn_id")
        if kind in CODEX_START:
            self.turn = turn
            self.running.clear()
            self.state, self.started, self.done_at = "thinking", stamp, 0
            self.asked_at, self.question_id = 0, ""
        elif self.turn and turn and self.turn != turn:
            return
        elif kind == "turn_aborted":
            self.state = ""
        elif self.state and self.state != "done":
            self.finish(stamp)

    def take(self, entry):
        if self.provider == "codex":
            self.take_codex(entry)
            return
        kind = entry.get("type")
        if kind not in ("user", "assistant") or entry.get("isSidechain"):
            return
        stamp = iso_ms(entry.get("timestamp"))
        self.cwd = entry.get("cwd") or self.cwd
        self.updated = max(self.updated, stamp)
        content = (entry.get("message") or {}).get("content")
        if kind == "user":
            if isinstance(content, str) or not any(b.get("type") == "tool_result" for b in content or []):
                text = content if isinstance(content, str) else " ".join(
                    b.get("text", "") for b in content or [] if b.get("type") == "text")
                if text.startswith("[Request interrupted"):
                    self.finish(stamp)
                elif not entry.get("isMeta") and text.strip() and not text.lstrip().startswith("<"):
                    # A new turn.
                    self.running, self.state, self.started, self.done_at = {}, "thinking", stamp, 0
                    self.asked_at, self.question_id = 0, ""
                return
            for block in content:
                if block.get("type") == "tool_result":
                    self.running.pop(block.get("tool_use_id"), None)
            if self.state != "done":
                self.state = self.working()
            return
        for block in content or []:
            if block.get("type") == "tool_use":
                self.start_tool(block.get("id"), block.get("name") in ASKING_TOOLS, stamp)
                self.started = self.started or stamp
        if (entry.get("message") or {}).get("stop_reason") in ("end_turn", "stop_sequence", "max_tokens", "refusal"):
            self.finish(stamp)
        elif self.state != "done" or self.running:
            self.state = self.working()
            self.done_at = 0

    def start_tool(self, call, asking, stamp):
        if asking and call and call != self.question_id:
            self.asked_at, self.question_id = stamp, call
        self.running[call] = asking

    def working(self):
        if any(self.running.values()):
            return "asking"
        return "tool" if self.running else "thinking"

    def finish(self, stamp):
        self.running = {}
        self.state = "done"
        self.done_at = stamp

    def shown(self, now):
        if not self.state:
            return False
        if self.state == "done":
            return now - self.done_at < DONE_KEPT * 1000
        # Waiting on you, nothing's written for as long as you take.
        idle = ASKING_IDLE if self.state == "asking" else IDLE
        return now - max(self.updated, mtime_ms(self.path)) < idle * 1000

    def snapshot(self):
        return {"id": f"{self.provider}:{self.id}", "name": self.name, "provider": self.provider,
                "state": self.state, "cwd": self.cwd, "transcript": str(self.path),
                "origin": self.origin, "startedAt": self.started,
                "doneAt": self.done_at, "updatedAt": self.updated,
                "askedAt": self.asked_at, "questionId": self.question_id}


def mtime_ms(path):
    try:
        return int(os.path.getmtime(path) * 1000)
    except OSError:
        return 0


def roots():
    seen, out = set(), []
    for root in [os.environ.get("CLAUDE_CONFIG_DIR", "")] + glob.glob(os.path.expanduser("~/.claude*")):
        projects = os.path.join(root, "projects") if root else ""
        real = os.path.realpath(projects) if projects and os.path.isdir(projects) else ""
        if real and real not in seen:
            seen.add(real)
            out.append(real)
    return out


def codex_paths():
    root = Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex") / "sessions"
    today = date.today()
    for day in (today, today - timedelta(days=1)):
        yield from (root / day.strftime("%Y/%m/%d")).glob("rollout-*.jsonl")


def ipc_sessions(now):
    root = Path(os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}") / "island-activities"
    for file in root.glob("*.json"):
        try:
            data = json.loads(file.read_text())
            age = now - data["updatedAt"]
            pid = data["pid"]
            if data["state"] in ("done", "failed"):
                if age >= DONE_KEPT * 1000:
                    continue
            elif pid:
                tick = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()[19]
                if tick != data["processStart"]:
                    continue
            elif age >= ASKING_IDLE * 1000:
                continue
            fields = ("id", "name", "state", "startedAt", "doneAt", "updatedAt")
            optional = {key: data.get(key) for key in ("window", "ownerPid", "ownerStart", "askedAt")}
            yield {**{key: data[key] for key in fields}, **optional, "provider": "external"}
        except (OSError, ValueError, TypeError, IndexError, KeyError):
            continue


def main():
    sessions, hot, last, listed = {}, [], None, 0
    while True:
        if os.getppid() == 1:
            return
        now = time.time()
        if now - listed >= RELIST:
            listed = now
            # Followed as long as one could still be shown: a question can
            # wait on you longer than a session may otherwise sit quiet.
            candidates = [(p, "claude") for r in roots() for p in glob.glob(os.path.join(r, "*", "*.jsonl"))]
            candidates.extend((str(p), "codex") for p in codex_paths())
            hot = [(p, provider) for p, provider in candidates
                   if now * 1000 - mtime_ms(p) < max(IDLE, ASKING_IDLE) * 1000]
            sessions = {p: sessions[p] if p in sessions else Session(p, provider) for p, provider in hot}
        for session in sessions.values():
            session.read()
        stamp = now_ms()
        shown = [s.snapshot() for s in sessions.values() if not s.hidden and s.shown(stamp)]
        shown.extend(ipc_sessions(stamp))
        shown.sort(key=lambda s: (s["state"] in ("done", "failed"), -s["updatedAt"]))
        out = json.dumps({"sessions": shown[:MAX_SESSIONS]}, separators=(",", ":"))
        if out != last:
            last = out
            try:
                print(out, flush=True)
            except BrokenPipeError:
                os._exit(0)
        time.sleep(POLL)


if __name__ == "__main__":
    main()
