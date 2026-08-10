import importlib.util
import json
import os
import stat
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


update = load("control_bar_update", ROOT / "hooks" / "update.py")
installer = load("control_bar_installer", ROOT / "scripts" / "install_hooks.py")
context_snapshot = load("control_bar_context", ROOT / "scripts" / "context_snapshot.py")
appserver_snapshot = load("control_bar_appserver", ROOT / "scripts" / "appserver_snapshot.py")


class HookTests(unittest.TestCase):
    def test_lifecycle_and_metrics(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            transcript = root / "rollout.jsonl"
            transcript.write_text("\n".join([
                json.dumps({"type": "event_msg", "payload": {"type": "task_started", "model_context_window": 1000}}),
                json.dumps({"type": "event_msg", "payload": {"type": "token_count", "info": {
                    "model_context_window": 1000,
                    "last_token_usage": {"total_tokens": 426},
                }}}),
            ]), encoding="utf-8")
            payload = {
                "session_id": "thr_test",
                "turn_id": "turn_1",
                "cwd": "/tmp/example",
                "transcript_path": str(transcript),
                "model": "gpt-test",
                "permission_mode": "default",
            }
            path = update.process_event("UserPromptSubmit", payload, root / "state")
            state = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(state["state"], "thinking")
            self.assertEqual(state["contextPercent"], 43)
            self.assertEqual(state["project"], "example")

            payload["tool_name"] = "Bash"
            update.process_event("PreToolUse", payload, root / "state")
            state = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(state["state"], "tool")
            self.assertEqual(state["label"], "Running command")

            update.process_event("PermissionRequest", payload, root / "state")
            state = json.loads(path.read_text(encoding="utf-8"))
            self.assertEqual(state["state"], "permission")

            update.process_event("SessionEnd", payload, root / "state")
            self.assertFalse(path.exists())

    def test_installer_preserves_foreign_hooks_and_is_idempotent(self):
        original = {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "other-tool"}]}]}}
        first = installer.merged(original, ROOT, False)
        second = installer.merged(first, ROOT, False)
        handlers = [handler for group in second["hooks"]["Stop"] for handler in group["hooks"]]
        self.assertEqual(sum(installer.is_ours(handler) for handler in handlers), 1)
        self.assertTrue(any(handler["command"] == "other-tool" for handler in handlers))
        removed = installer.merged(second, ROOT, True)
        handlers = [handler for group in removed["hooks"]["Stop"] for handler in group["hooks"]]
        self.assertFalse(any(installer.is_ours(handler) for handler in handlers))

    def test_installed_bundle_hook_is_quoted_and_removable(self):
        app = Path("/tmp/My Applications/CodexControlBar.app")
        script = app / "Contents/Resources/update.py"
        document = installer.merged({}, ROOT, False, hook_script=script, app_path=app)
        handlers = [
            handler for groups in document["hooks"].values()
            for group in groups for handler in group["hooks"]
        ]
        self.assertTrue(all(installer.is_ours(handler) for handler in handlers))
        self.assertTrue(all("CODEX_CONTROL_BAR_APP=" in handler["command"] for handler in handlers))
        self.assertTrue(all("My Applications" in handler["command"] for handler in handlers))
        self.assertNotIn("hooks", installer.merged(document, ROOT, True))

    def test_safe_session_id(self):
        self.assertEqual(update.safe_id("../thr bad"), "..thrbad")

    def test_surface_comes_from_rollout_session_meta(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            desktop = root / "desktop.jsonl"
            desktop.write_text(json.dumps({"type": "session_meta", "payload": {
                "originator": "Codex Desktop", "source": "vscode",
            }}) + "\n", encoding="utf-8")
            cli = root / "cli.jsonl"
            cli.write_text(json.dumps({"type": "session_meta", "payload": {
                "originator": "codex-tui", "source": "cli",
            }}) + "\n", encoding="utf-8")

            self.assertEqual(update.transcript_surface(desktop), "APP")
            self.assertEqual(update.transcript_surface(cli), "CLI")
            with mock.patch.dict(os.environ, {"__CFBundleIdentifier": "", "TERM_PROGRAM": ""}):
                self.assertEqual(update.session_surface(desktop), "APP")
                self.assertEqual(update.session_surface(cli), "CLI")

    def test_reads_git_branch_without_spawning_git(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / ".git").mkdir()
            (root / ".git" / "HEAD").write_text("ref: refs/heads/feature/menu-polish\n", encoding="utf-8")
            nested = root / "Sources" / "UI"
            nested.mkdir(parents=True)
            self.assertEqual(update.git_branch(str(nested)), "feature/menu-polish")

    def test_context_snapshot_uses_latest_rollout_usage(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            state = root / "state"
            state.mkdir()
            transcript = root / "rollout.jsonl"
            transcript.write_text(json.dumps({
                "timestamp": "2026-08-07T10:00:00Z",
                "payload": {"type": "token_count", "info": {
                    "model_context_window": 1000,
                    "last_token_usage": {"total_tokens": 731},
                }},
            }) + "\n", encoding="utf-8")
            (state / "thread.json").write_text(json.dumps({
                "sessionId": "thread-1", "transcript": str(transcript),
            }), encoding="utf-8")
            snapshot = context_snapshot.collect(state)
            self.assertEqual(snapshot["sessions"]["thread-1"]["contextPercent"], 73)
            self.assertEqual(snapshot["sessions"]["thread-1"]["contextSource"], "rollout token_count · last usage")

    def test_context_uses_last_request_not_cumulative_usage(self):
        with tempfile.TemporaryDirectory() as temporary:
            transcript = Path(temporary) / "rollout.jsonl"
            transcript.write_text(json.dumps({
                "payload": {"type": "token_count", "info": {
                    "model_context_window": 1000,
                    "last_token_usage": {"total_tokens": 420},
                    "total_token_usage": {"total_tokens": 99999},
                }},
            }) + "\n", encoding="utf-8")
            metrics = update.transcript_metrics(transcript)
            self.assertEqual(metrics["tokens"], 420)
            self.assertEqual(metrics["contextPercent"], 42)

    def test_appserver_response_timeout_is_not_blocking(self):
        process = subprocess.Popen(
            ["/bin/cat"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            text=True, bufsize=1,
        )
        started = time.monotonic()
        try:
            with self.assertRaises(TimeoutError):
                appserver_snapshot.response(process, 99, timeout=0.03)
        finally:
            process.terminate()
            process.wait(timeout=1)
            if process.stdin:
                process.stdin.close()
            if process.stdout:
                process.stdout.close()
        self.assertLess(time.monotonic() - started, 0.5)

    def test_appserver_response_skips_noise_and_unmatched_ids(self):
        process = subprocess.Popen(
            ["/bin/cat"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            text=True, bufsize=1,
        )
        try:
            assert process.stdin is not None
            process.stdin.write("not-json\n")
            process.stdin.write(json.dumps({"id": 7, "result": {"ignored": True}}) + "\n")
            process.stdin.write(json.dumps({"id": 42, "result": {"ok": True}}) + "\n")
            process.stdin.flush()
            self.assertEqual(appserver_snapshot.response(process, 42, timeout=0.5), {"ok": True})
        finally:
            process.terminate()
            process.wait(timeout=1)
            if process.stdin:
                process.stdin.close()
            if process.stdout:
                process.stdout.close()

    def test_snapshot_failure_preserves_last_successful_data(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "snapshot.json"
            previous = {
                "updatedAt": 123,
                "rateLimits": {"rateLimits": {"primary": {"usedPercent": 12}}},
                "mcp": {"data": [{"name": "local"}]},
            }
            output.write_text(json.dumps(previous), encoding="utf-8")
            with mock.patch.dict(os.environ, {"CODEX_CONTROL_BAR_SNAPSHOT": str(output)}), \
                 mock.patch.object(appserver_snapshot, "collect", side_effect=TimeoutError("offline")):
                self.assertEqual(appserver_snapshot.main(), 1)
            recovered = json.loads(output.read_text(encoding="utf-8"))
            self.assertEqual(recovered["rateLimits"], previous["rateLimits"])
            self.assertEqual(recovered["mcp"], previous["mcp"])
            self.assertIn("offline", recovered["error"])
            self.assertIn("failedAt", recovered)

    def test_atomic_snapshot_permissions_and_replacement(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary) / "snapshot.json"
            appserver_snapshot.write_atomic(output, {"sequence": 1})
            appserver_snapshot.write_atomic(output, {"sequence": 2})
            self.assertEqual(json.loads(output.read_text(encoding="utf-8")), {"sequence": 2})
            self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)

    def test_context_tolerates_corrupt_and_partial_rollout_lines(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            state = root / "state"
            state.mkdir()
            transcript = root / "rollout.jsonl"
            transcript.write_text("broken\n" + json.dumps({
                "payload": {"type": "token_count", "info": {
                    "model_context_window": 2000,
                    "last_token_usage": {"total_tokens": 1500},
                }},
            }) + "\n{partial", encoding="utf-8")
            (state / "thread.json").write_text(json.dumps({
                "sessionId": "thread-1", "transcript": str(transcript),
            }), encoding="utf-8")
            snapshot = context_snapshot.collect(state)
            self.assertEqual(snapshot["sessions"]["thread-1"]["contextPercent"], 75)

    def test_context_reads_latest_usage_from_large_rollout_tail(self):
        with tempfile.TemporaryDirectory() as temporary:
            transcript = Path(temporary) / "rollout.jsonl"
            padding = ("x" * 1000 + "\n") * 1600
            latest = json.dumps({"payload": {"type": "token_count", "info": {
                "model_context_window": 1000,
                "last_token_usage": {"total_tokens": 880},
            }}})
            transcript.write_text(padding + latest + "\n", encoding="utf-8")
            metrics = update.transcript_metrics(transcript)
            self.assertEqual(metrics["contextPercent"], 88)


if __name__ == "__main__":
    unittest.main()
