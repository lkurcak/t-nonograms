# t-nonograms

Nonograms, a game and a solver, written in [T](https://github.com/lkurcak/t-lang),
partly to find out what writing a game in T is like. What got in the way is
in [FRICTION.md](FRICTION.md).

```text
> play 1
Puzzle: plus, 5x5
    1 3 5 3 1
  +----------
1 | . . . . .  1
3 | . . . . .  2
5 | . . . . .  3
3 | . . . . .  4
1 | . . . . .  5
  +----------
    1 2 3 4 5
> f 3 1-5
...
```

Each row and column has a clue: the lengths of its blocks of filled cells,
in order, with at least one empty cell between blocks. Fill in the grid so
that every clue holds, and a picture appears.

It reads commands, one a line, after a `> ` prompt. `help` lists them:

- `list`, `play N` or `play NAME`: the puzzles drawn in `puzzles.t`;
- `new W H [SEED]`: a random puzzle, one a person can solve a line at a time;
- `load` or `load FILE`: type in a puzzle's clues, or read them from a file
  (the rows on its first line, the columns on its second, as in
  `tests/corner.txt`), and the solver says whether it has no solution, one,
  or more than one;
- `f ROW COL`, `x ROW COL`, `c ROW COL`: fill, mark empty, or clear cells,
  each of `ROW` and `COL` a number or a range like `2-5`;
- `undo`, `hint` (one cell a single row or column makes certain, or where a
  mistake is), `check`, `solve`, `show`, `quit`.
- `keys`, at a terminal: play with the arrow keys (or `hjkl`/`wasd`); `f`
  or space fills, `x` marks empty, `c` clears, `u` undoes, `q` or Escape
  goes back to commands.

Random puzzles are seeded from the operating system's entropy, so each run
gives different ones; `new W H SEED` gives the same one again.

## How the solver works

`line.t` solves one line: given its clue and what's known of its cells, it
finds every cell that is the same in all ways to place the blocks. It does
that without listing them, with a table from each end (can the first `i`
cells hold the first `j` blocks?, and the same from the right), so a line of
`n` cells and `k` blocks takes about `n * k` steps.

`solve.t` solves lines until none says anything new, re-solving only the
lines that crossed a change. If cells are still unknown it guesses one, both
ways, and solves on, stopping at two solutions, which is what deciding
uniqueness needs. A budget of guesses keeps a bad puzzle from hanging the
game.

## Running it

```sh
t main.t                 # play, interpreted
t build main.t && ./t-nonograms   # play, compiled through C: much faster
tests/run.sh             # check: no warnings, formatted, `t test` passes,
                         # and tests/input.txt gives tests/expected.txt,
                         # interpreted and compiled
BLESS=1 tests/run.sh     # rewrite tests/expected.txt
```

Big random puzzles (`new 20 20`) take seconds interpreted and milliseconds
compiled.

It needs `t` 0.66.0, the version CI pins (in `.github/workflows/t.yml`),
and a C compiler for `t build`.
