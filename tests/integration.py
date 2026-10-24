"""CLI, reproducibility, real-PTY rendering/input, and cleanup regressions."""
import json
import re
import signal
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

from terminal import Terminal

BINARY = Path(__file__).resolve().parents[1] / "tetris"
TIMING_FIELDS = {"elapsed_ms", "mean_plan_us", "max_plan_us"}


class Integration(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="tetris-test-")
        self.cwd = Path(self.temp.name)
        self.best = self.cwd / ".tetris_highscore"
        self.best.write_text("7777\n")

    def tearDown(self):
        self.temp.cleanup()

    def run_cli(self, *args):
        return subprocess.run(
            [str(BINARY), *args], cwd=self.cwd,
            capture_output=True, text=True, timeout=15,
        )

    def benchmark(self, seed, pieces=160):
        result = self.run_cli("--benchmark", str(pieces), str(seed))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        data = json.loads(result.stdout)
        self.assertEqual(data["seed"], seed)
        self.assertEqual(data["pieces"], pieces)
        self.assertEqual(data["status"], "limit")
        self.assertLessEqual(data["lines"] * 10, pieces * 4)
        self.assertGreater(data["nodes"], data["placements"])
        self.assertGreater(data["mean_plan_us"], 0)
        self.assertLessEqual(data["height"], 20)
        return {k: v for k, v in data.items() if k not in TIMING_FIELDS}

    def test_help_and_non_tty(self):
        result = self.run_cli("--help")
        self.assertEqual(result.returncode, 0)
        self.assertIn("No GPU", result.stdout)
        result = self.run_cli()
        self.assertEqual(result.returncode, 1)
        self.assertIn("interactive terminals", result.stderr)

    def test_invalid_arguments(self):
        cases = [
            ("--bogus",), ("--testx",), ("--test", "extra"),
            ("--demo", "extra"), ("--benchmark", "0"),
            ("--benchmark", "1000001"), ("--benchmark", "-1"),
            ("--benchmark", ""), ("--benchmark", "1", "0"),
            ("--benchmark", "1", "18446744073709551616"),
            ("--benchmark", "1", "1x"), ("--benchmark", "1", "2", "3"),
            ("--versus", "0"), ("--arena-demo", "junk"),
            ("--versus", "1", "2"), ("--match", "0"),
            ("--match", "3601"), ("--match", "1", "0"),
            ("--match", "1", "18446744073709551616"),
            ("--multiverse", "0"), ("--multiverse", "1", "2"),
            ("--forecast", "junk"), ("--forecast", "-1"),
            ("--forecast", "18446744073709551616"),
        ]
        for args in cases:
            with self.subTest(args=args):
                result = self.run_cli(*args)
                self.assertEqual(result.returncode, 2)
                self.assertEqual(result.stdout, "")

    def test_reproducible_search_and_highscore_isolation(self):
        a = self.benchmark(42)
        b = self.benchmark(42)
        self.assertEqual(a, b)
        hashes = {a["board_hash"]}
        for seed in (1, 2026, 18446744073709551615):
            hashes.add(self.benchmark(seed)["board_hash"])
        self.assertGreater(len(hashes), 1)
        self.assertEqual(self.best.read_text(), "7777\n")
        self.assertEqual(list(self.cwd.iterdir()), [self.best])

    def test_demo_pause_takeover_pace_and_cleanup(self):
        with Terminal(BINARY, self.cwd, ["--demo"]) as tty:
            tty.until(lambda: "ASSISTED RUN" in tty.screen.text)
            self.assertIn("AUTOPILOT / ACTIVE", tty.screen.text)
            self.assertIn("CPU ONLY / NO GPU", tty.screen.text)
            self.assertEqual(tty.screen.scrolls, 0)
            tty.send(b"p", 0.2)
            self.assertIn("PAUSED", tty.screen.lines[-1])
            paused = tty.screen.text
            tty.pump(0.8)
            self.assertEqual(tty.screen.text, paused)
            tty.send(b"p")
            tty.send(b"a")
            self.assertIn("HINTS ON / YOU PLAY", tty.screen.text)
            tty.send(b"h")
            self.assertIn("MANUAL / HINTS OFF", tty.screen.text)
            self.assertIn("PRESS H TO SEE A PLAN", tty.screen.text)
            self.assertIn("NEXT MOVE   --", tty.screen.text)
            tty.send(b"]")
            self.assertIn("50 ms / move", tty.screen.text)
            tty.send(b"[")
            self.assertIn("75 ms / move", tty.screen.text)
            tty.send(b"+")
            self.assertIn("25ms [-/+]", tty.screen.text)
            tty.send(b"-")
            self.assertIn("30ms [-/+]", tty.screen.text)
            tty.send(b"q")
            self.assertEqual(tty.process.wait(timeout=2), 0)
            tty.assert_restored()
        self.assertEqual(self.best.read_text(), "7777\n")

    def test_one_piece_stops_and_restart_resets_assistance(self):
        with Terminal(BINARY, self.cwd) as tty:
            tty.until(lambda: "HUMAN / LIVE" in tty.screen.text)
            tty.send(b"n")
            tty.until(lambda: "HINTS ON / YOU PLAY" in tty.screen.text and
                      "ASSISTED RUN" in tty.screen.text)
            self.assertNotIn("PLAYING ONE PIECE", tty.screen.text)
            tty.send(b"r")
            self.assertIn("HUMAN / LIVE", tty.screen.text)
            self.assertIn("SCORE   0", tty.screen.text)
            tty.send(b"9")
            self.assertIn("LEVEL   9", tty.screen.text)

    def test_resize_compact_and_suspension(self):
        with Terminal(BINARY, self.cwd, ["--demo"]) as tty:
            tty.until(lambda: "C O P I L O T" in tty.screen.text)
            tty.resize(60, 24)
            self.assertNotIn("C O P I L O T", tty.screen.text)
            self.assertIn("SCORE", tty.screen.text)
            self.assertEqual(tty.screen.scrolls, 0)
            tty.resize(40, 15)
            self.assertIn("Game suspended.", tty.screen.text)
            frozen = tty.screen.text
            tty.pump(0.7)
            self.assertEqual(tty.screen.text, frozen)
            tty.resize(80, 24)
            self.assertIn("C O P I L O T", tty.screen.text)
            self.assertIn("AUTOPILOT / ACTIVE", tty.screen.text)
            self.assertEqual(tty.screen.scrolls, 0)

    def test_fragmented_arrow_sequence(self):
        with Terminal(BINARY, self.cwd) as tty:
            tty.until(lambda: "HUMAN / LIVE" in tty.screen.text)
            tty.send(b"h", 0.04)

            def active_columns():
                return [x for row in tty.screen.cells[2:5] for x, cell in enumerate(row[3:23])
                        if cell[2] not in ("#101419", "#1c1c1c", "#262626")]

            before = active_columns()
            self.assertTrue(before)
            tty.send(b"\x1b", 0.035)
            tty.send(b"[", 0.035)
            tty.send(b"D", 0.035)
            after = active_columns()
            self.assertEqual(after, [x - 2 for x in before])

    def test_ctrl_c_and_signals_restore_terminal(self):
        for sig in (None, signal.SIGTERM, signal.SIGHUP, signal.SIGINT, signal.SIGQUIT):
            with self.subTest(signal=sig), Terminal(BINARY, self.cwd, ["--demo"]) as tty:
                tty.until(lambda: "C O P I L O T" in tty.screen.text)
                if sig is None:
                    tty.send(b"\x03")
                else:
                    tty.process.send_signal(sig)
                    tty.pump(0.1)
                self.assertEqual(tty.process.wait(timeout=2), 0 if sig is None else 128 + sig)
                tty.assert_restored()

    def test_arena_determinism_and_conservation(self):
        first = None
        for seed in (42, 1, 2026, 42):
            result = self.run_cli("--match", "60", str(seed))
            self.assertEqual(result.returncode, 0, result.stderr)
            data = json.loads(result.stdout)
            data.pop("wall_ms")
            self.assertEqual(data["mode"], "arena")
            self.assertGreater(data["simulated_ms"], 0)
            self.assertLessEqual(data["simulated_ms"], 60000)
            self.assertIn(data["result"], ("left", "right", "draw"))
            left, right = data["left"], data["right"]
            for player in (left, right):
                self.assertEqual(
                    player["cells"],
                    player["pieces"] * 4 + player["received"] * 9 - player["lines"] * 10,
                    "Locked blocks must be conserved through attacks and line clears",
                )
                self.assertGreater(player["pieces"], 0)
            self.assertEqual(left["sent"], right["cancelled"] + right["received"] + right["pending"])
            self.assertEqual(right["sent"], left["cancelled"] + left["received"] + left["pending"])
            if seed == 42:
                if first is None:
                    first = data
                else:
                    self.assertEqual(data, first)
        self.assertEqual(self.best.read_text(), "7777\n")

    def test_arena_replay_branch_pause_and_output_backpressure(self):
        with Terminal(BINARY, self.cwd, ["--arena-demo", "42"]) as tty:
            tty.until(lambda: "GET READY /" in tty.screen.text)
            tty.send(b"p")
            self.assertIn("PAUSED / P TO RESUME", tty.screen.text)
            frozen = tty.screen.text
            tty.pump(0.25)
            self.assertEqual(tty.screen.text, frozen)
            tty.send(b"p")
            tty.until(lambda: "BATTLE / LIVE" in tty.screen.text, timeout=5)
            # Deliberately stop draining output: the writer must handle EAGAIN
            # without losing bytes, chopping UTF-8, or emitting broken CSI.
            time.sleep(0.2)
            tty.pump(0.3)
            tty.send(b"3")
            self.assertIn("CPU / LEVEL 3", tty.screen.text)
            tty.pump(0.5)
            tty.send(b"v")
            self.assertIn("REPLAY /", tty.screen.text)
            tty.send(b"\x1b[D")
            self.assertIn("REPLAY / FROZEN", tty.screen.text)
            frozen = tty.screen.text
            tty.pump(0.2)
            self.assertEqual(tty.screen.text, frozen)
            tty.send(b"\r")
            self.assertIn("BRANCH 1", tty.screen.text)
            self.assertEqual(tty.screen.lines[15][27:54].strip(), "BATTLE / LIVE")
            self.assertRegex(
                tty.screen.lines[4][27:54].strip(),
                r"^SCORE\s+(0|[1-9]\d*) : (0|[1-9]\d*)$",
            )
            self.assertEqual(tty.screen.scrolls, 0)
            tty.send(b"q")
            self.assertEqual(tty.process.wait(timeout=2), 0)
            tty.assert_restored()
        self.assertEqual(self.best.read_text(), "7777\n")

    def test_arena_resize_takeover_and_rematch(self):
        with Terminal(BINARY, self.cwd, ["--arena-demo", "2026"]) as tty:
            tty.until(lambda: "BATTLE / LIVE" in tty.screen.text, timeout=5)
            tty.send(b"a")
            self.assertIn("YOU / HUMAN", tty.screen.text)
            tty.send(b"h")
            tty.resize(60, 24)
            self.assertIn("Resize to 80 x 24.", tty.screen.text)
            frozen = tty.screen.text
            tty.pump(0.3)
            self.assertEqual(tty.screen.text, frozen)
            tty.resize(80, 24)
            self.assertIn("BATTLE / LIVE", tty.screen.text)
            tty.send(b"r")
            self.assertIn("ROUND 2", tty.screen.text)
            self.assertIn("GET READY /", tty.screen.text)
            self.assertEqual(tty.screen.scrolls, 0)
            tty.process.send_signal(signal.SIGTERM)
            tty.pump(0.15)
            self.assertEqual(tty.process.wait(timeout=2), 143)
            tty.assert_restored()

    def test_multiverse_forecast_determinism_and_conservation(self):
        first = None
        for seed in (2026, 42, 1, 18446744073709551615, 2026):
            result = self.run_cli("--forecast", str(seed))
            self.assertEqual(result.returncode, 0, result.stderr)
            data = json.loads(result.stdout)
            self.assertEqual(data["mode"], "multiverse")
            self.assertEqual(data["futures"], 3)
            self.assertEqual(data["horizon_ms"], 8000)
            self.assertEqual(len({b["first_landing"] for b in data["branches"]}), 3)
            self.assertGreater(len({b["left"]["board_hash"] for b in data["branches"]}), 1)
            for branch in data["branches"]:
                self.assertGreater(branch["simulated_ms"], 0)
                self.assertLessEqual(branch["simulated_ms"], 8000)
                left, right = branch["left"], branch["right"]
                for player in (left, right):
                    self.assertEqual(
                        player["cells"], player["pieces"] * 4 +
                        player["received"] * 9 - player["lines"] * 10,
                    )
                self.assertEqual(left["sent"], right["cancelled"] + right["received"] + right["pending"])
                self.assertEqual(right["sent"], left["cancelled"] + left["received"] + left["pending"])
            data.pop("build_ms")
            if seed == 2026:
                if first is None:
                    first = data
                else:
                    self.assertEqual(data, first)
        self.assertEqual(self.best.read_text(), "7777\n")
        self.assertEqual(list(self.cwd.iterdir()), [self.best])

    def test_multiverse_scrub_select_and_exact_visible_jump(self):
        forecast = json.loads(self.run_cli("--forecast", "2026").stdout)
        with Terminal(BINARY, self.cwd, ["--multiverse", "2026"]) as tty:
            tty.until(lambda: "MULTIVERSE" in tty.screen.text, timeout=5)
            self.assertIn("▶ FUTURE 01", tty.screen.lines[0])
            # Freeze, scrub past the endpoint, and select the third future.
            tty.send(b" " + b"\x1b[A" * 70 + b"3", 0.2)
            self.assertIn("MULTIVERSE +8.00s", tty.screen.text)
            self.assertIn("▶ FUTURE 03", tty.screen.lines[0])
            frozen = tty.screen.text
            tty.pump(0.2)
            self.assertEqual(tty.screen.text, frozen)
            for x in (2, 29, 56):
                self.assertEqual(tty.screen.cells[1][x][0], "┌")
                self.assertEqual(tty.screen.cells[1][x+21][0], "┐")
                self.assertEqual(tty.screen.cells[22][x+21][0], "┘")
            expected_board = [row[57:77] for row in tty.screen.cells[2:22]]
            tty.send(b"\rp", 0.15)  # Commit and immediately freeze before a tick.
            self.assertIn("BRANCH 1", tty.screen.text)
            self.assertIn("PAUSED / P TO RESUME", tty.screen.text)
            self.assertEqual([row[3:23] for row in tty.screen.cells[2:22]], expected_board)
            chosen = forecast["branches"][2]
            self.assertEqual(
                tty.screen.lines[5][27:54].strip(),
                f'LINES  {chosen["left"]["lines"]} : {chosen["right"]["lines"]}',
            )
            self.assertEqual(tty.screen.scrolls, 0)
            # A second multiverse can be explored and cancelled while paused.
            original = tty.screen.text
            tty.send(b"m", 0.6)
            self.assertIn("MULTIVERSE", tty.screen.text)
            tty.send(b"m", 0.1)
            self.assertEqual(tty.screen.text, original)
            tty.send(b"q")
            self.assertEqual(tty.process.wait(timeout=2), 0)
            tty.assert_restored()
        self.assertEqual(self.best.read_text(), "7777\n")

    def test_multiverse_resize_split_arrows_and_restart(self):
        with Terminal(BINARY, self.cwd, ["--multiverse", "42"]) as tty:
            tty.until(lambda: "MULTIVERSE" in tty.screen.text, timeout=5)
            tty.send(b" " + b"\x1b[B" * 70)
            self.assertIn("MULTIVERSE +0.00s", tty.screen.text)
            tty.send(b"\x1b", 0.04)
            tty.send(b"[", 0.04)
            tty.send(b"C", 0.04)
            self.assertIn("▶ FUTURE 02", tty.screen.lines[0])
            tty.send(b"\x1b[D\x1b[D")
            self.assertIn("▶ FUTURE 03", tty.screen.lines[0])
            tty.send(b"9adswzbchv")  # Ordinary game controls cannot leak through.
            self.assertIn("MULTIVERSE +0.00s", tty.screen.text)
            frozen = tty.screen.text
            tty.resize(60, 20)
            self.assertIn("Both games suspended.", tty.screen.text)
            tty.pump(0.1)
            tty.resize(80, 24)
            self.assertEqual(tty.screen.text, frozen)
            tty.send(b"r")
            self.assertIn("ROUND 2", tty.screen.text)
            self.assertIn("GET READY /", tty.screen.text)
            self.assertEqual(tty.screen.scrolls, 0)
            tty.process.send_signal(signal.SIGTERM)
            tty.pump(0.1)
            self.assertEqual(tty.process.wait(timeout=2), 143)
            tty.assert_restored()


if __name__ == "__main__":
    unittest.main(verbosity=2)
