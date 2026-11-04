#!/bin/sh
# Checks t-nonograms: it type-checks with no warnings, it's formatted, its
# tests pass, and its output for tests/input.txt is tests/expected.txt. Run
# from anywhere; `t` must be on PATH.
# BLESS=1 rewrites tests/expected.txt with what it prints now.
set -eu
cd "$(dirname "$0")/.."

t check --deny-warnings main.t
t fmt --check ./*.t
t test --deny-warnings main.t

# The game's output, with each line of tests/input.txt after the prompt
# that asked for it (`> `, `rows> ` or `cols> `), as at a terminal, where
# what's typed is echoed.
transcript() {
    "$@" < tests/input.txt |
        awk 'NR == FNR { input[FNR] = $0; next }
             {
                 line = $0
                 while (match(line, /^(> |rows> |cols> )/)) {
                     n++
                     print substr(line, 1, RLENGTH) input[n]
                     line = substr(line, RLENGTH + 1)
                 }
                 if (line != "" || $0 == "") print line
             }' tests/input.txt -
}

if [ "${BLESS:-}" = 1 ]; then
    transcript t main.t > tests/expected.txt
    echo "wrote tests/expected.txt"
    exit 0
fi

transcript t main.t > tests/actual.txt
if ! diff -u tests/expected.txt tests/actual.txt; then
    echo "FAIL: output differs from tests/expected.txt"
    exit 1
fi

# Compiled through C, it must do just what the interpreter does.
t build -o tests/nonograms main.t
transcript tests/nonograms > tests/actual.txt
if ! diff -u tests/expected.txt tests/actual.txt; then
    echo "FAIL: the compiled game's output differs from tests/expected.txt"
    exit 1
fi
rm tests/actual.txt tests/nonograms
echo "ok"
