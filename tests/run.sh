#!/bin/sh
# Checks t-nonograms: it type-checks with no warnings, it's formatted, its
# tests pass, its output for tests/input.txt is tests/expected.txt, and
# `keys` plays on a terminal (tests/terminal.py). Run from anywhere; `t`
# must be on PATH, and python3, for the terminal.
# BLESS=1 rewrites tests/expected.txt with what it prints now.
set -eu
cd "$(dirname "$0")/.."

t check --deny-warnings main.t
t fmt --check ./*.t
t test --deny-warnings main.t

# The game's output: its input isn't a terminal, so it echoes each line of
# tests/input.txt after the prompt that asked for it (`> `, `rows> ` or
# `cols> `), as a terminal would.
transcript() {
    "$@" < tests/input.txt
}

# `t main.t` compiles the game; `--interp` runs it in the interpreter,
# which checks as it goes what the checker proved.
if [ "${BLESS:-}" = 1 ]; then
    transcript t --interp main.t > tests/expected.txt
    echo "wrote tests/expected.txt"
    exit 0
fi

transcript t --interp main.t > tests/actual.txt
if ! diff -u tests/expected.txt tests/actual.txt; then
    echo "FAIL: output differs from tests/expected.txt"
    exit 1
fi

# Compiled through C, as `t main.t` runs it, it must do just what the
# interpreter does; and play with the keys on a terminal.
t build -o tests/nonograms main.t
transcript tests/nonograms > tests/actual.txt
if ! diff -u tests/expected.txt tests/actual.txt; then
    echo "FAIL: the compiled game's output differs from tests/expected.txt"
    exit 1
fi
python3 -I tests/terminal.py tests/nonograms
rm tests/actual.txt tests/nonograms
echo "ok"
