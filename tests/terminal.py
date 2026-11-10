"""Plays `keys` on a pseudo-terminal: moves, fills, leaves with escape, and
then solves a puzzle with the keys alone; checks that `keys` drew on the
other screen and went back, and that the terminal's settings after are as
before.

    python3 -I tests/terminal.py tests/nonograms
"""

import fcntl
import os
import pty
import re
import select
import struct
import sys
import termios
import time

ESC = "\x1b"
UP, DOWN, RIGHT, LEFT = ESC + "[A", ESC + "[B", ESC + "[C", ESC + "[D"


def play(argv, keys, rows=24, cols=80):
    """Runs `argv` on a terminal `cols` by `rows`, typing `keys`, each a
    string, or a number of seconds to wait; gives its output, and how it
    stopped, and the terminal's settings before and after."""
    pid, fd = pty.fork()
    if pid == 0:
        os.execv(argv[0], argv)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    before = termios.tcgetattr(fd)
    out = b""

    def read_for(seconds):
        nonlocal out
        end = time.time() + seconds
        while time.time() < end:
            ready, _, _ = select.select([fd], [], [], 0.05)
            if ready:
                try:
                    data = os.read(fd, 1 << 16)
                except OSError:
                    return
                if not data:
                    return
                out += data

    read_for(0.5)
    for k in keys:
        if isinstance(k, (int, float)):
            read_for(k)
        else:
            os.write(fd, k.encode())
            read_for(0.2)
    deadline = time.time() + 10
    while True:
        done, status = os.waitpid(pid, os.WNOHANG)
        if done:
            break
        if time.time() > deadline:
            os.kill(pid, 9)
            sys.exit("FAIL: the game didn't stop when told to")
        read_for(0.1)
    read_for(0.2)
    after = termios.tcgetattr(fd)
    os.close(fd)
    return out.decode("utf-8", "replace"), status, before, after


def plain(text):
    """`text` without colours and cursor moves."""
    return re.sub(ESC + r"\[[0-9;?]*[A-Za-z]", "", text)


def check(what, ok):
    if not ok:
        sys.exit("FAIL: " + what)


def moves(cells):
    """The keys that fill `cells`, each (column, row) from 0, from the top
    left: arrows, vi's letters, and `wasd`, in turn, and `f` or space."""
    keys, x, y = [], 0, 0
    ways = [
        {"right": RIGHT, "left": LEFT, "down": DOWN, "up": UP},
        {"right": "l", "left": "h", "down": "j", "up": "k"},
        {"right": "d", "left": "a", "down": "s", "up": "w"},
    ]
    for i, (cx, cy) in enumerate(cells):
        way = ways[i % len(ways)]
        keys += [way["right"]] * max(cx - x, 0) + [way["left"]] * max(x - cx, 0)
        keys += [way["down"]] * max(cy - y, 0) + [way["up"]] * max(y - cy, 0)
        keys.append("f" if i % 2 == 0 else " ")
        x, y = cx, cy
    return keys


def main():
    exe = sys.argv[1]
    # Fill one cell, leave with escape on its own, and see the board.
    text, status, before, after = play(
        [exe], ["play 1\n", "keys\n", RIGHT, RIGHT, "f", ESC, 0.3, "show\n", "quit\n"]
    )
    check("it stopped cleanly", os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0)
    check("keys used the other screen", ESC + "[?1049h" in text)
    check("keys went back to the first screen", ESC + "[?1049l" in text)
    check("it showed the cursor again", ESC + "[?25h" in text)
    check("the terminal's as it was", before == after)
    back = plain(text.split(ESC + "[?1049l")[-1])
    check("the fill was kept", "#" in back)
    # The plus, solved with the keys alone.
    plus = [(2, 0), (1, 1), (2, 1), (3, 1), (0, 2), (1, 2), (2, 2), (3, 2), (4, 2)]
    plus += [(1, 3), (2, 3), (3, 3), (2, 4)]
    text, status, _, after = play([exe], ["play 1\n", "keys\n"] + moves(plus) + [0.3, "quit\n"])
    check("it stopped cleanly", os.WIFEXITED(status) and os.WEXITSTATUS(status) == 0)
    check("solving it left keys", ESC + "[?1049l" in text)
    check("it said it's solved", "olved" in plain(text.split(ESC + "[?1049l")[-1]))
    check("the terminal's as it was", before == after)
    print("terminal ok")


main()
