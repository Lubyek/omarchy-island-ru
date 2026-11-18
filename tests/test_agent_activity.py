"""Regression checks for the agent events that drive Island banners."""
from datetime import datetime, timezone
import importlib.util
import os
from pathlib import Path
import subprocess
from tempfile import TemporaryDirectory
import unittest
from unittest import mock

PLUGIN = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("activity", PLUGIN / "addons/agents/live.py")
activity = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(activity)


def record(kind, payload):
    return {
        "type": kind, "payload": payload,
        "timestamp": datetime.now(timezone.utc).isoformat(timespec="milliseconds"),
    }


class AgentActivityTests(unittest.TestCase):
    def test_codex_async_question_survives_immediate_tool_result(self):
        session = activity.Session("rollout-fixture.jsonl", "codex")
        session.take(record("event_msg", {"type": "task_started", "turn_id": "one"}))
        session.take(record("response_item", {
            "type": "custom_tool_call", "call_id": "question",
            "name": "functions.request_user_input_async",
        }))
        self.assertEqual(session.state, "asking")
        asked_at = session.snapshot()["askedAt"]
        self.assertGreater(asked_at, 0)
        session.take(record("response_item", {
            "type": "custom_tool_call_output", "call_id": "question",
        }))
        session.take(record("event_msg", {"type": "task_complete", "turn_id": "one"}))
        self.assertEqual(session.state, "done")
        self.assertEqual(session.snapshot()["askedAt"], asked_at)
        session.take(record("event_msg", {"type": "task_started", "turn_id": "two"}))
        self.assertEqual(session.snapshot()["askedAt"], 0)

    def test_claude_question_uses_the_tool_call_identity(self):
        session = activity.Session("claude-fixture.jsonl", "claude")
        session.take({
            "type": "assistant", "timestamp": "2026-01-01T12:00:00.000Z",
            "message": {"content": [{"type": "tool_use", "name": "AskUserQuestion", "id": "question"}]},
        })
        self.assertEqual(session.state, "asking")
        self.assertEqual(session.snapshot()["questionId"], "question")

    def test_cli_waiting_and_completion_are_idempotent(self):
        with TemporaryDirectory() as directory:
            environment = dict(os.environ, XDG_RUNTIME_DIR=directory, HYPRLAND_INSTANCE_SIGNATURE="")
            bridge = PLUGIN / "companion/island-activity"

            def publish(state):
                subprocess.run([bridge, state, "test", "Fixture"], check=True, env=environment)
                with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": directory}):
                    return next(activity.ipc_sessions(activity.now_ms()))

            publish("start")
            question = publish("waiting")
            self.assertGreater(question["askedAt"], 0)
            self.assertEqual(publish("waiting")["askedAt"], question["askedAt"])
            complete = publish("done")
            self.assertEqual(complete["askedAt"], question["askedAt"])
            self.assertEqual(publish("done"), complete)
