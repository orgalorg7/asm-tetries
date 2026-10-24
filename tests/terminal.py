"""Small VT screen/PTY harness for this application's actual ANSI output.

Only the emitted VT commands are needed; unknown control sequences fail loudly.
No third-party packages or display server are required.
"""
import codecs
import fcntl
import html
import os
import pty
import re
import select
import struct
import subprocess
import termios
import time
from pathlib import Path

DEFAULT_FG = "#dce1e8"
DEFAULT_BG = "#101419"
BASE_COLORS = [
    "#101419", "#e56b7a", "#a5d68b", "#f1cf75",
    "#75b6e7", "#c8a5dc", "#80cfd0", "#dce1e8",
    "#65717e", "#ff8b98", "#c0eaa7", "#ffe09a",
    "#a0d1f7", "#e4c4f5", "#afe9e9", "#ffffff",
]


def color(index):
    if index < 16:
        return BASE_COLORS[index]
    if index >= 232:
        v = 8 + (index - 232) * 10
        return f"#{v:02x}{v:02x}{v:02x}"
    n = index - 16
    levels = (0, 95, 135, 175, 215, 255)
    rgb = (levels[n // 36], levels[(n // 6) % 6], levels[n % 6])
    return "#" + "".join(f"{v:02x}" for v in rgb)


class Screen:
    def __init__(self, cols=80, rows=24):
        self.decoder = codecs.getincrementaldecoder("utf-8")()
        self.pending = ""
        self.scrolls = 0
        self.frames = 0
        self.fg, self.bg, self.bold = DEFAULT_FG, DEFAULT_BG, False
        self.resize(cols, rows)

    def blank(self):
        return (" ", DEFAULT_FG, DEFAULT_BG, False)

    def resize(self, cols, rows):
        self.cols, self.rows = cols, rows
        self.cells = [[self.blank() for _ in range(cols)] for _ in range(rows)]
        self.x = self.y = 0
        self.wrap = False

    def linefeed(self):
        self.y += 1
        if self.y >= self.rows:
            self.cells.pop(0)
            self.cells.append([self.blank() for _ in range(self.cols)])
            self.y = self.rows - 1
            self.scrolls += 1

    def feed(self, data):
        self.pending += self.decoder.decode(data)
        i = 0
        while i < len(self.pending):
            ch = self.pending[i]
            if ch == "\x1b":
                match = re.match(r"\x1b\[([0-9;?]*)([A-Za-z])", self.pending[i:])
                if not match:
                    if len(self.pending) - i > 32:
                        raise AssertionError(f"Unknown escape: {self.pending[i:i+32]!r}")
                    break
                self.command(*match.groups())
                i += len(match[0])
                continue
            if ch == "\r":
                self.x = 0
                self.wrap = False
            elif ch == "\n":
                self.linefeed()
                self.wrap = False
            elif ch >= " ":
                if self.wrap:
                    self.x = 0
                    self.linefeed()
                    self.wrap = False
                self.cells[self.y][self.x] = (ch, self.fg, self.bg, self.bold)
                if self.x == self.cols - 1:
                    self.wrap = True
                else:
                    self.x += 1
            i += 1
        self.pending = self.pending[i:]

    def command(self, args, op):
        if args.startswith("?") and op in "hl":
            return  # Alternate screen/cursor visibility, no text positioning.
        values = [int(n) if n else 0 for n in args.split(";")]
        n = values[0]
        if op in "Hf":
            self.y = min(self.rows - 1, max(0, n - 1))
            self.x = min(self.cols - 1, max(0, (values[1] if len(values) > 1 else 1) - 1))
            self.wrap = False
            self.frames += 1
        elif op == "G":
            self.x = min(self.cols - 1, max(0, n - 1))
            self.wrap = False
        elif op == "J":
            if n == 2:
                self.cells = [[self.blank() for _ in range(self.cols)] for _ in range(self.rows)]
            elif n == 0:
                self.cells[self.y][self.x:] = [self.blank() for _ in range(self.cols - self.x)]
                for row in range(self.y + 1, self.rows):
                    self.cells[row] = [self.blank() for _ in range(self.cols)]
            else:
                raise AssertionError(f"Unsupported erase J{n}")
        elif op == "K" and n == 0:
            self.cells[self.y][self.x:] = [self.blank() for _ in range(self.cols - self.x)]
        elif op == "m":
            i = 0
            while i < len(values):
                v = values[i]
                if v == 0:
                    self.fg, self.bg, self.bold = DEFAULT_FG, DEFAULT_BG, False
                elif v == 1:
                    self.bold = True
                elif v in (2, 22):
                    self.bold = False
                elif v in (38, 48) and values[i + 1] == 5:
                    if v == 38:
                        self.fg = color(values[i + 2])
                    else:
                        self.bg = color(values[i + 2])
                    i += 2
                elif 30 <= v <= 37:
                    self.fg = color(v - 30)
                elif 40 <= v <= 47:
                    self.bg = color(v - 40)
                elif 90 <= v <= 97:
                    self.fg = color(v - 90 + 8)
                elif 100 <= v <= 107:
                    self.bg = color(v - 100 + 8)
                else:
                    raise AssertionError(f"Unsupported SGR {v}")
                i += 1
        else:
            raise AssertionError(f"Unsupported CSI {args}{op}")

    @property
    def lines(self):
        return ["".join(cell[0] for cell in row).rstrip() for row in self.cells]

    @property
    def text(self):
        return "\n".join(self.lines)

    def save_svg(self, path):
        """Export the captured terminal cells, including real ANSI colors."""
        cw, ch, pad = 10, 22, 28
        width, height = self.cols * cw + pad * 2, self.rows * ch + pad * 2
        svg = [
            f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
            "<title>Assembly Tetris — captured live terminal frame</title>",
            f'<rect width="{width}" height="{height}" rx="14" fill="{DEFAULT_BG}"/>',
            '<g font-family="DejaVu Sans Mono, monospace" font-size="16">',
        ]
        for y, row in enumerate(self.cells):
            for x, (letter, fg, bg, bold) in enumerate(row):
                px, py = pad + x * cw, pad + y * ch
                if bg != DEFAULT_BG:
                    svg.append(f'<rect x="{px}" y="{py}" width="{cw}" height="{ch}" fill="{bg}"/>')
                if letter != " ":
                    weight = ' font-weight="700"' if bold else ""
                    svg.append(f'<text x="{px}" y="{py+17}" fill="{fg}"{weight}>{html.escape(letter)}</text>')
        svg.extend(["</g>", "</svg>"])
        Path(path).write_text("\n".join(svg) + "\n")


class Terminal:
    def __init__(self, binary, cwd, args=(), cols=80, rows=24):
        self.master, self.slave = pty.openpty()
        self.original_termios = termios.tcgetattr(self.slave)
        self.original_flags = fcntl.fcntl(self.slave, fcntl.F_GETFL)
        self.screen = Screen(cols, rows)
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        self.raw = bytearray()
        self.process = subprocess.Popen(
            [str(binary), *args], cwd=cwd,
            stdin=self.slave, stdout=self.slave, stderr=self.slave,
        )

    def pump(self, seconds=0.1):
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            timeout = min(0.03, max(0, deadline - time.monotonic()))
            if select.select([self.master], [], [], timeout)[0]:
                try:
                    data = os.read(self.master, 65536)
                except OSError:
                    break
                self.raw.extend(data)
                self.screen.feed(data)

    def until(self, predicate, timeout=3):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            self.pump(0.03)
            if predicate():
                return
            if self.process.poll() is not None:
                break
        raise AssertionError(f"Terminal condition timed out:\n{self.screen.text}")

    def send(self, data, seconds=0.08):
        os.write(self.master, data)
        self.pump(seconds)

    def resize(self, cols, rows):
        # Drain a complete preceding frame before changing the emulated screen.
        self.pump(0.03)
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        self.screen.resize(cols, rows)
        self.pump(0.12)

    def assert_restored(self):
        assert termios.tcgetattr(self.slave) == self.original_termios, "termios leaked"
        assert fcntl.fcntl(self.slave, fcntl.F_GETFL) == self.original_flags, "fd flags leaked"
        assert b"\x1b[?25h" in self.raw, "cursor was not restored"
        assert b"\x1b[?1049l" in self.raw, "alternate screen was not restored"

    def close(self):
        try:
            if self.process.poll() is None:
                self.send(b"q")
                self.process.wait(timeout=2)
            self.pump(0.03)
        finally:
            if self.process.poll() is None:
                self.process.kill()
                self.process.wait()
            os.close(self.master)
            os.close(self.slave)

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
